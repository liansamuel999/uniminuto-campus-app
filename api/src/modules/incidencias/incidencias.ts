import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface Incidencia {
  id: string;
  descripcion: string;
  estado: string;
  resolucion: string | null;
  creadaEn: string;
  actualizadaEn: string;
  usuario: string;
  atendidaPor: string | null;
}

export interface RepositorioIncidencias {
  crear(uidFirebase: string, descripcion: string): Promise<Incidencia>;
  listarPropias(uidFirebase: string): Promise<Incidencia[]>;
  listarPorEstado(estado: string | undefined): Promise<Incidencia[]>;
  actualizar(uidSoporte: string, id: string, datos: { estado: string; resolucion?: string }): Promise<Incidencia | null>;
}

const iso = (valor: string | Date) =>
  (valor instanceof Date ? valor : new Date(valor)).toISOString();

const CAMPOS = `
  i.id, i.descripcion, i.estado, i.resolucion, i.creada_en, i.actualizada_en,
  u.nombres || ' ' || u.apellidos AS usuario,
  a.nombres || ' ' || a.apellidos AS atendida_por
`;

/** Incidencias reportadas por los usuarios y gestionadas por Soporte (D-50). */
export function crearRepositorioIncidencias(pool: Pool): RepositorioIncidencias {
  const aIncidencia = (fila: {
    id: string;
    descripcion: string;
    estado: string;
    resolucion: string | null;
    creada_en: string | Date;
    actualizada_en: string | Date;
    usuario: string;
    atendida_por: string | null;
  }): Incidencia => ({
    id: fila.id,
    descripcion: fila.descripcion,
    estado: fila.estado,
    resolucion: fila.resolucion,
    creadaEn: iso(fila.creada_en),
    actualizadaEn: iso(fila.actualizada_en),
    usuario: fila.usuario,
    atendidaPor: fila.atendida_por,
  });

  return {
    async crear(uidFirebase, descripcion) {
      const resultado = await pool.query<{
        id: string;
        descripcion: string;
        estado: string;
        resolucion: string | null;
        creada_en: string | Date;
        actualizada_en: string | Date;
        usuario: string;
        atendida_por: string | null;
      }>(
        `INSERT INTO incidencia (usuario_id, descripcion)
         SELECT u.id, $2 FROM usuario u WHERE u.uid_firebase = $1
         RETURNING id, descripcion, estado, resolucion, creada_en, actualizada_en,
                   (SELECT nombres || ' ' || apellidos FROM usuario WHERE id = incidencia.usuario_id) AS usuario,
                   NULL::text AS atendida_por`,
        [uidFirebase, descripcion],
      );
      const fila = resultado.rows[0];
      if (!fila) throw errores.noEncontrado('El usuario autenticado no está registrado');
      return aIncidencia(fila);
    },

    async listarPropias(uidFirebase) {
      const resultado = await pool.query(
        `SELECT ${CAMPOS}
         FROM incidencia i
         JOIN usuario u ON u.id = i.usuario_id
         LEFT JOIN usuario a ON a.id = i.atendida_por
         WHERE u.uid_firebase = $1
         ORDER BY i.creada_en DESC LIMIT 100`,
        [uidFirebase],
      );
      return resultado.rows.map(aIncidencia);
    },

    async listarPorEstado(estado) {
      const resultado = await pool.query(
        `SELECT ${CAMPOS}
         FROM incidencia i
         JOIN usuario u ON u.id = i.usuario_id
         LEFT JOIN usuario a ON a.id = i.atendida_por
         WHERE ($1::text IS NULL OR i.estado = $1)
         ORDER BY i.creada_en DESC LIMIT 200`,
        [estado ?? null],
      );
      return resultado.rows.map(aIncidencia);
    },

    async actualizar(uidSoporte, id, datos) {
      const resultado = await pool.query<{
        id: string;
        descripcion: string;
        estado: string;
        resolucion: string | null;
        creada_en: string | Date;
        actualizada_en: string | Date;
        usuario: string;
        atendida_por: string | null;
      }>(
        `UPDATE incidencia
         SET estado = $2, resolucion = $3, actualizada_en = now(),
             atendida_por = (SELECT id FROM usuario WHERE uid_firebase = $4)
         WHERE id = $1
         RETURNING id, descripcion, estado, resolucion, creada_en, actualizada_en,
                   (SELECT nombres || ' ' || apellidos FROM usuario WHERE id = incidencia.usuario_id) AS usuario,
                   (SELECT nombres || ' ' || apellidos FROM usuario WHERE id = incidencia.atendida_por) AS atendida_por`,
        [id, datos.estado, datos.resolucion ?? null, uidSoporte],
      );
      const fila = resultado.rows[0];
      return fila ? aIncidencia(fila) : null;
    },
  };
}

const esquemaCreacion = z
  .object({ descripcion: z.string().trim().min(10).max(2000) })
  .strict();

const esquemaActualizacion = z
  .object({
    estado: z.enum(['ABIERTA', 'EN_PROCESO', 'RESUELTA', 'CERRADA']),
    resolucion: z.string().trim().max(2000).optional(),
  })
  .strict();

const ESTADOS = ['ABIERTA', 'EN_PROCESO', 'RESUELTA', 'CERRADA'] as const;

/** Rutas de incidencias (§7.7, D-50). */
export function registrarRutasIncidencias(
  app: FastifyInstance,
  repo: RepositorioIncidencias,
): void {
  app.post('/api/v1/incidencias', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const { descripcion } = esquemaCreacion.parse(peticion.body ?? {});
    const incidencia = await repo.crear(peticion.actor!.uid, descripcion);
    return respuesta.code(201).send(incidencia);
  });

  app.get('/api/v1/incidencias', { preHandler: app.autenticar }, async (peticion) => {
    const { estado } = z
      .object({ estado: z.enum(ESTADOS).optional() })
      .parse(peticion.query ?? {});
    const esSoporte = peticion.actor?.roles.includes('SOPORTE') ?? false;
    if (esSoporte) return repo.listarPorEstado(estado);
    return repo.listarPropias(peticion.actor!.uid);
  });

  app.put(
    '/api/v1/incidencias/:id',
    { preHandler: [app.autenticar, app.requerirRoles('SOPORTE')] },
    async (peticion) => {
      const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
      const datos = esquemaActualizacion.parse(peticion.body ?? {});
      const incidencia = await repo.actualizar(peticion.actor!.uid, id, datos);
      if (!incidencia) throw errores.noEncontrado('La incidencia no existe');
      return incidencia;
    },
  );
}
