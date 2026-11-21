import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface PerfilUsuario {
  id: string;
  nombres: string;
  apellidos: string;
  correo: string;
  documento: string | null;
  codigoInstitucional: string | null;
  fotoKey: string | null;
  estado: string;
  programa: { id: string; nombre: string } | null;
  roles: string[];
}

export interface CambiosPerfil {
  nombres?: string;
  apellidos?: string;
  fotoKey?: string | null;
}

/** Contrato del repositorio: permite probar las rutas sin base de datos. */
export interface RepositorioPerfil {
  obtenerPorUid(uidFirebase: string): Promise<PerfilUsuario | null>;
  actualizarPorUid(uidFirebase: string, cambios: CambiosPerfil): Promise<PerfilUsuario | null>;
}

const CONSULTA_PERFIL = `
  SELECT
    u.id,
    u.nombres,
    u.apellidos,
    u.correo,
    u.documento,
    u.codigo_institucional AS "codigoInstitucional",
    u.foto_key AS "fotoKey",
    u.estado,
    p.id AS "programaId",
    p.nombre AS "programaNombre",
    (
      SELECT COALESCE(array_agg(r.nombre ORDER BY r.nombre), '{}')
      FROM usuario_rol ur
      JOIN rol r ON r.id = ur.rol_id
      WHERE ur.usuario_id = u.id
    ) AS roles
  FROM usuario u
  LEFT JOIN programa p ON p.id = u.programa_id
`;

interface FilaPerfil {
  id: string;
  nombres: string;
  apellidos: string;
  correo: string;
  documento: string | null;
  codigoInstitucional: string | null;
  fotoKey: string | null;
  estado: string;
  programaId: string | null;
  programaNombre: string | null;
  roles: string[] | null;
}

function aPerfil(fila: FilaPerfil): PerfilUsuario {
  return {
    id: fila.id,
    nombres: fila.nombres,
    apellidos: fila.apellidos,
    correo: fila.correo,
    documento: fila.documento,
    codigoInstitucional: fila.codigoInstitucional,
    fotoKey: fila.fotoKey,
    estado: fila.estado,
    programa:
      fila.programaId && fila.programaNombre
        ? { id: fila.programaId, nombre: fila.programaNombre }
        : null,
    roles: fila.roles ?? [],
  };
}

/** Repositorio real sobre CockroachDB. */
export function crearRepositorioPerfil(pool: Pool): RepositorioPerfil {
  return {
    async obtenerPorUid(uidFirebase) {
      const resultado = await pool.query<FilaPerfil>(`${CONSULTA_PERFIL} WHERE u.uid_firebase = $1`, [
        uidFirebase,
      ]);
      const fila = resultado.rows[0];
      return fila ? aPerfil(fila) : null;
    },

    async actualizarPorUid(uidFirebase, cambios) {
      const asignaciones: string[] = [];
      const valores: unknown[] = [];

      if (cambios.nombres !== undefined) {
        valores.push(cambios.nombres);
        asignaciones.push(`nombres = $${valores.length}`);
      }
      if (cambios.apellidos !== undefined) {
        valores.push(cambios.apellidos);
        asignaciones.push(`apellidos = $${valores.length}`);
      }
      if (cambios.fotoKey !== undefined) {
        valores.push(cambios.fotoKey);
        asignaciones.push(`foto_key = $${valores.length}`);
      }

      if (asignaciones.length > 0) {
        valores.push(uidFirebase);
        await pool.query(
          `UPDATE usuario SET ${asignaciones.join(', ')}, actualizado_en = now()
           WHERE uid_firebase = $${valores.length}`,
          valores,
        );
      }

      const resultado = await pool.query<FilaPerfil>(`${CONSULTA_PERFIL} WHERE u.uid_firebase = $1`, [
        uidFirebase,
      ]);
      const fila = resultado.rows[0];
      return fila ? aPerfil(fila) : null;
    },
  };
}

const esquemaCambios = z
  .object({
    nombres: z.string().trim().min(2).max(80).optional(),
    apellidos: z.string().trim().min(2).max(80).optional(),
    fotoKey: z
      .string()
      .trim()
      .max(200)
      .regex(/^perfiles\/[\w.-]+\.(jpg|jpeg|png|webp)$/i, 'fotoKey debe ser perfiles/<id>.jpg')
      .nullable()
      .optional(),
  })
  .strict();

/** Rutas de perfil propio (§7.7). Requieren sesión; solo se edita lo propio. */
export function registrarRutasPerfil(app: FastifyInstance, repositorio: RepositorioPerfil): void {
  app.get('/api/v1/mi-perfil', { preHandler: app.autenticar }, async (peticion) => {
    const perfil = await repositorio.obtenerPorUid(peticion.actor!.uid);
    if (!perfil) {
      throw errores.noEncontrado('El usuario autenticado no está registrado en la base de datos');
    }
    return perfil;
  });

  app.put('/api/v1/mi-perfil', { preHandler: app.autenticar }, async (peticion) => {
    const cambios = esquemaCambios.parse(peticion.body ?? {});
    const intentaCambiarIdentidad = cambios.nombres !== undefined || cambios.apellidos !== undefined;
    if (intentaCambiarIdentidad) {
      throw errores.prohibido(
        'Los datos de identidad no se editan desde la aplicación. Solicita el cambio a la oficina de registro.',
      );
    }
    const perfil = await repositorio.actualizarPorUid(peticion.actor!.uid, cambios);
    if (!perfil) {
      throw errores.noEncontrado('El usuario autenticado no está registrado en la base de datos');
    }
    return perfil;
  });
}
