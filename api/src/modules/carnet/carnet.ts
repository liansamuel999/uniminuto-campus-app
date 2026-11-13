import { createHash } from 'node:crypto';
import type { Pool } from 'pg';
import { z } from 'zod';

import type { JwkEc } from '../../config/institution_keys.js';
import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';
import type { FirmanteCarnet } from '../../lib/pki.js';

export interface CarnetResumen {
  id: string;
  codigoBarras: string;
  estado: string;
  vigenteHasta: string;
}

export interface DispositivoResumen {
  id: string;
  nombre: string;
  vinculadoEn: string;
}

export interface CertificadoResumen {
  jwt: string;
  kid: string;
  emitidoEn: string;
  expiraEn: string;
}

export interface ResumenCarnet {
  carnet: CarnetResumen;
  dispositivo: DispositivoResumen | null;
  certificado: CertificadoResumen | null;
}

export interface DatosVinculacion {
  nombreDispositivo: string;
  clavePublicaJwk: JwkEc;
}

export interface RepositorioCarnet {
  obtenerResumen(uidFirebase: string): Promise<ResumenCarnet | null>;
  vincular(uidFirebase: string, datos: DatosVinculacion): Promise<ResumenCarnet>;
  renovar(uidFirebase: string): Promise<ResumenCarnet>;
  revocar(uidFirebase: string, dispositivoId: string, puedeRevocarAjeno: boolean): Promise<void>;
}

/** Huella JWK (RFC 7638) para deduplicar claves públicas. */
export function huellaJwk(jwk: Pick<JwkEc, 'kty' | 'crv' | 'x' | 'y'>): string {
  const canonico = JSON.stringify({ crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y });
  return createHash('sha256').update(canonico).digest('base64url');
}

export const esquemaClavePublica = z
  .object({
    kty: z.literal('EC'),
    crv: z.literal('P-256'),
    x: z.string().min(40).max(120),
    y: z.string().min(40).max(120),
  })
  .passthrough();

export const esquemaVinculacion = z
  .object({
    nombreDispositivo: z.string().trim().min(2).max(80),
    clavePublicaJwk: esquemaClavePublica,
  })
  .strict();

interface FilaCarnet {
  id: string;
  codigo_barras: string;
  estado: string;
  vigente_hasta: string | Date;
  usuario_id: string;
}

interface FilaDispositivo {
  id: string;
  nombre_dispositivo: string;
  vinculado_en: string | Date;
}

interface FilaCertificado {
  jwt_firmado: string;
  kid_institucional: string;
  emitido_en: string | Date;
  expira_en: string | Date;
}

function aFechaIso(valor: string | Date): string {
  return valor instanceof Date ? valor.toISOString() : new Date(valor).toISOString();
}

/** Implementación sobre CockroachDB + firma institucional. */
export function crearRepositorioCarnet(pool: Pool, firmante: FirmanteCarnet): RepositorioCarnet {
  async function carnetPorUid(uidFirebase: string): Promise<FilaCarnet | null> {
    const resultado = await pool.query<FilaCarnet>(
      `SELECT c.id, c.codigo_barras, c.estado, c.vigente_hasta, c.usuario_id
       FROM carnet c JOIN usuario u ON u.id = c.usuario_id
       WHERE u.uid_firebase = $1`,
      [uidFirebase],
    );
    return resultado.rows[0] ?? null;
  }

  async function resumenDe(carnet: FilaCarnet): Promise<ResumenCarnet> {
    const dispositivo = await pool.query<FilaDispositivo>(
      `SELECT id, nombre_dispositivo, vinculado_en FROM dispositivo
       WHERE carnet_id = $1 AND estado = 'ACTIVO'`,
      [carnet.id],
    );
    const activo = dispositivo.rows[0] ?? null;

    let certificado: CertificadoResumen | null = null;
    if (activo) {
      const fila = await pool.query<FilaCertificado>(
        `SELECT jwt_firmado, kid_institucional, emitido_en, expira_en
         FROM certificado_carnet WHERE dispositivo_id = $1
         ORDER BY emitido_en DESC LIMIT 1`,
        [activo.id],
      );
      const cert = fila.rows[0];
      if (cert) {
        certificado = {
          jwt: cert.jwt_firmado,
          kid: cert.kid_institucional,
          emitidoEn: aFechaIso(cert.emitido_en),
          expiraEn: aFechaIso(cert.expira_en),
        };
      }
    }

    return {
      carnet: {
        id: carnet.id,
        codigoBarras: carnet.codigo_barras,
        estado: carnet.estado,
        vigenteHasta: aFechaIso(carnet.vigente_hasta),
      },
      dispositivo: activo
        ? {
            id: activo.id,
            nombre: activo.nombre_dispositivo,
            vinculadoEn: aFechaIso(activo.vinculado_en),
          }
        : null,
      certificado,
    };
  }

  return {
    async obtenerResumen(uidFirebase) {
      const carnet = await carnetPorUid(uidFirebase);
      return carnet ? resumenDe(carnet) : null;
    },

    async vincular(uidFirebase, datos) {
      return withTx(pool, async (cliente) => {
        const usuario = await cliente.query<{ id: string; codigo_institucional: string | null; nombres: string }>(
          `SELECT id, codigo_institucional, nombres FROM usuario WHERE uid_firebase = $1`,
          [uidFirebase],
        );
        const filaUsuario = usuario.rows[0];
        if (!filaUsuario) {
          throw errores.noEncontrado('El usuario autenticado no está registrado en la base de datos');
        }

        let carnet = await cliente.query<FilaCarnet>(
          'SELECT id, codigo_barras, estado, vigente_hasta, usuario_id FROM carnet WHERE usuario_id = $1',
          [filaUsuario.id],
        );
        if (!carnet.rows[0]) {
          const codigo = `UNI-${filaUsuario.codigo_institucional ?? filaUsuario.id.slice(0, 8)}`;
          const creado = await cliente.query<FilaCarnet>(
            `INSERT INTO carnet (usuario_id, codigo_barras, estado, vigente_hasta)
             VALUES ($1, $2, 'ACTIVO', (now() + interval '1 year')::date)
             RETURNING id, codigo_barras, estado, vigente_hasta, usuario_id`,
            [filaUsuario.id, codigo],
          );
          carnet = creado;
        }
        const filaCarnet = carnet.rows[0]!;

        if (filaCarnet.estado !== 'ACTIVO') {
          throw errores.conflicto(`El carnet está ${filaCarnet.estado} y no se puede vincular un dispositivo`);
        }

        // Un solo dispositivo ACTIVO por carnet: se revoca el anterior en la misma transacción.
        await cliente.query(
          `UPDATE dispositivo SET estado = 'REVOCADO', revocado_en = now()
           WHERE carnet_id = $1 AND estado = 'ACTIVO'`,
          [filaCarnet.id],
        );

        const huella = huellaJwk(datos.clavePublicaJwk);
        const nuevo = await cliente.query<{ id: string; vinculado_en: string | Date }>(
          `INSERT INTO dispositivo (carnet_id, nombre_dispositivo, clave_publica_jwk, huella)
           VALUES ($1, $2, $3::jsonb, $4)
           RETURNING id, vinculado_en`,
          [filaCarnet.id, datos.nombreDispositivo, JSON.stringify(datos.clavePublicaJwk), huella],
        );
        const dispositivo = nuevo.rows[0]!;

        const certificado = await firmante.firmar({
          carnetId: filaCarnet.id,
          codigo: filaCarnet.codigo_barras,
          estado: filaCarnet.estado,
          dispositivo: datos.clavePublicaJwk,
        });
        await cliente.query(
          `INSERT INTO certificado_carnet (dispositivo_id, kid_institucional, emitido_en, expira_en, jwt_firmado)
           VALUES ($1, $2, $3, $4, $5)`,
          [dispositivo.id, certificado.kid, certificado.emitidoEn, certificado.expiraEn, certificado.jwt],
        );

        await cliente.query(
          `INSERT INTO evento_auditoria (actor_id, accion, recurso, resultado)
           VALUES ($1, 'VINCULAR_DISPOSITIVO', $2, 'OK')`,
          [filaUsuario.id, `dispositivo:${dispositivo.id}`],
        );

        return {
          carnet: {
            id: filaCarnet.id,
            codigoBarras: filaCarnet.codigo_barras,
            estado: filaCarnet.estado,
            vigenteHasta: aFechaIso(filaCarnet.vigente_hasta),
          },
          dispositivo: {
            id: dispositivo.id,
            nombre: datos.nombreDispositivo,
            vinculadoEn: aFechaIso(dispositivo.vinculado_en),
          },
          certificado: {
            jwt: certificado.jwt,
            kid: certificado.kid,
            emitidoEn: certificado.emitidoEn.toISOString(),
            expiraEn: certificado.expiraEn.toISOString(),
          },
        } satisfies ResumenCarnet;
      });
    },

    async renovar(uidFirebase) {
      return withTx(pool, async (cliente) => {
        const fila = await cliente.query<
          FilaCarnet & { dispositivo_id: string; clave_publica_jwk: JwkEc; nombre_dispositivo: string; vinculado_en: string | Date }
        >(
          `SELECT c.id, c.codigo_barras, c.estado, c.vigente_hasta, c.usuario_id,
                  d.id AS dispositivo_id, d.clave_publica_jwk, d.nombre_dispositivo, d.vinculado_en
           FROM carnet c
           JOIN usuario u ON u.id = c.usuario_id
           JOIN dispositivo d ON d.carnet_id = c.id AND d.estado = 'ACTIVO'
           WHERE u.uid_firebase = $1`,
          [uidFirebase],
        );
        const registrado = fila.rows[0];
        if (!registrado) {
          throw errores.conflicto('No hay un dispositivo activo vinculado para renovar el certificado');
        }
        if (registrado.estado !== 'ACTIVO') {
          throw errores.conflicto(`El carnet está ${registrado.estado}`);
        }

        const certificado = await firmante.firmar({
          carnetId: registrado.id,
          codigo: registrado.codigo_barras,
          estado: registrado.estado,
          dispositivo: registrado.clave_publica_jwk,
        });
        await cliente.query(
          `INSERT INTO certificado_carnet (dispositivo_id, kid_institucional, emitido_en, expira_en, jwt_firmado)
           VALUES ($1, $2, $3, $4, $5)`,
          [registrado.dispositivo_id, certificado.kid, certificado.emitidoEn, certificado.expiraEn, certificado.jwt],
        );

        return {
          carnet: {
            id: registrado.id,
            codigoBarras: registrado.codigo_barras,
            estado: registrado.estado,
            vigenteHasta: aFechaIso(registrado.vigente_hasta),
          },
          dispositivo: {
            id: registrado.dispositivo_id,
            nombre: registrado.nombre_dispositivo,
            vinculadoEn: aFechaIso(registrado.vinculado_en),
          },
          certificado: {
            jwt: certificado.jwt,
            kid: certificado.kid,
            emitidoEn: certificado.emitidoEn.toISOString(),
            expiraEn: certificado.expiraEn.toISOString(),
          },
        } satisfies ResumenCarnet;
      });
    },

    async revocar(uidFirebase, dispositivoId, puedeRevocarAjeno) {
      await withTx(pool, async (cliente) => {
        const fila = await cliente.query<{
          dispositivo_id: string;
          carnet_id: string;
          usuario_id: string;
          actor_id: string;
        }>(
          `SELECT d.id AS dispositivo_id, d.carnet_id, c.usuario_id, u.id AS actor_id
           FROM dispositivo d
           JOIN carnet c ON c.id = d.carnet_id
           JOIN usuario u ON u.uid_firebase = $1
           WHERE d.id = $2 AND d.estado = 'ACTIVO'`,
          [uidFirebase, dispositivoId],
        );
        const registrado = fila.rows[0];
        if (!registrado) {
          throw errores.noEncontrado('No existe un dispositivo activo con ese id');
        }
        const esPropietario = registrado.usuario_id === registrado.actor_id;
        if (!esPropietario && !puedeRevocarAjeno) {
          throw errores.prohibido('Solo puedes revocar tus propios dispositivos');
        }

        await cliente.query(
          `UPDATE dispositivo SET estado = 'REVOCADO', revocado_en = now(), revocado_por = $2 WHERE id = $1`,
          [dispositivoId, registrado.actor_id],
        );
        await cliente.query(
          `INSERT INTO lista_revocacion (carnet_id, motivo) VALUES ($1, $2)
           ON CONFLICT (carnet_id) DO UPDATE SET motivo = EXCLUDED.motivo, desde = now()`,
          [registrado.carnet_id, esPropietario ? 'REVOCADO_POR_USUARIO' : 'REVOCADO_POR_SOPORTE'],
        );
        await cliente.query(
          `INSERT INTO evento_auditoria (actor_id, accion, recurso, resultado)
           VALUES ($1, 'REVOCAR_DISPOSITIVO', $2, 'OK')`,
          [registrado.actor_id, `dispositivo:${dispositivoId}`],
        );
      });
    },
  };
}
