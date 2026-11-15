import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

/** Criterios de la evaluación docente (§4.2), todos en escala 1–5 (D-70). */
export const CRITERIOS_EVALUACION = [
  'dominio',
  'claridad',
  'metodologia',
  'evaluacion',
  'acompanamiento',
] as const;

export type CriterioEvaluacion = (typeof CRITERIOS_EVALUACION)[number];

/** Respuestas normalizadas: un valor 1–5 por criterio. */
export type RespuestasEvaluacion = Record<CriterioEvaluacion, number>;

export interface EvaluacionCreada {
  id: string;
  enviadaEn: string;
}

export interface ResumenDocente {
  docenteId: string;
  docente: string;
  evaluaciones: number;
  criterios: Record<CriterioEvaluacion, number>;
  promedio: number;
}

export interface RepositorioEvaluaciones {
  crear(
    uidFirebase: string,
    datos: { inscripcionId: string; respuestas: RespuestasEvaluacion; comentario?: string },
  ): Promise<EvaluacionCreada>;
  resumen(): Promise<ResumenDocente[]>;
}

export function crearRepositorioEvaluaciones(pool: Pool): RepositorioEvaluaciones {
  return {
    async crear(uidFirebase, datos) {
      const contexto = await pool.query<{ docente_id: string | null }>(
        `SELECT g.docente_id
         FROM inscripcion i
         JOIN grupo g ON g.id = i.grupo_id
         JOIN usuario u ON u.id = i.estudiante_id
         WHERE i.id = $1 AND u.uid_firebase = $2 AND i.estado = 'ACTIVA'`,
        [datos.inscripcionId, uidFirebase],
      );
      const fila = contexto.rows[0];
      if (!fila) throw errores.noEncontrado('La inscripción no existe o no pertenece al usuario');
      if (!fila.docente_id) throw errores.datosInvalidos('El grupo no tiene docente asignado');

      const existente = await pool.query(
        'SELECT 1 FROM evaluacion_docente WHERE inscripcion_id = $1',
        [datos.inscripcionId],
      );
      if ((existente.rowCount ?? 0) > 0) {
        throw errores.conflicto('Ya evaluaste al docente de esta asignatura');
      }

      const creada = await pool.query<{ id: string; enviada_en: string | Date }>(
        `INSERT INTO evaluacion_docente (inscripcion_id, docente_id, respuestas, comentario)
         VALUES ($1, $2, $3::jsonb, $4)
         ON CONFLICT (inscripcion_id) DO NOTHING
         RETURNING id, enviada_en`,
        [datos.inscripcionId, fila.docente_id, JSON.stringify(datos.respuestas), datos.comentario ?? null],
      );
      const insertada = creada.rows[0];
      if (!insertada) throw errores.conflicto('Ya evaluaste al docente de esta asignatura');

      return {
        id: insertada.id,
        enviadaEn: (insertada.enviada_en instanceof Date
          ? insertada.enviada_en
          : new Date(insertada.enviada_en)
        ).toISOString(),
      };
    },

    async resumen() {
      const resultado = await pool.query<{
        docente_id: string;
        docente: string;
        evaluaciones: string;
        dominio: string | null;
        claridad: string | null;
        metodologia: string | null;
        evaluacion: string | null;
        acompanamiento: string | null;
      }>(
        `SELECT d.id AS docente_id, d.nombres || ' ' || d.apellidos AS docente,
                COUNT(*)::int AS evaluaciones,
                ROUND(AVG((e.respuestas->>'dominio')::numeric), 2) AS dominio,
                ROUND(AVG((e.respuestas->>'claridad')::numeric), 2) AS claridad,
                ROUND(AVG((e.respuestas->>'metodologia')::numeric), 2) AS metodologia,
                ROUND(AVG((e.respuestas->>'evaluacion')::numeric), 2) AS evaluacion,
                ROUND(AVG((e.respuestas->>'acompanamiento')::numeric), 2) AS acompanamiento
         FROM evaluacion_docente e
         JOIN usuario d ON d.id = e.docente_id
         GROUP BY d.id
         ORDER BY COUNT(*) DESC, docente`,
      );

      return resultado.rows.map((fila) => {
        const criterios = {
          dominio: Number(fila.dominio ?? 0),
          claridad: Number(fila.claridad ?? 0),
          metodologia: Number(fila.metodologia ?? 0),
          evaluacion: Number(fila.evaluacion ?? 0),
          acompanamiento: Number(fila.acompanamiento ?? 0),
        };
        const valores = CRITERIOS_EVALUACION.map((criterio) => criterios[criterio]);
        return {
          docenteId: fila.docente_id,
          docente: fila.docente,
          evaluaciones: Number(fila.evaluaciones),
          criterios,
          promedio: Number((valores.reduce((suma, valor) => suma + valor, 0) / valores.length).toFixed(2)),
        };
      });
    },
  };
}

const criterio = z.number().int().min(1).max(5);

const esquemaEvaluacion = z
  .object({
    inscripcionId: z.string().uuid(),
    respuestas: z
      .object({
        dominio: criterio,
        claridad: criterio,
        metodologia: criterio,
        evaluacion: criterio,
        acompanamiento: criterio,
      })
      .strict(),
    comentario: z.string().trim().max(1000).optional(),
  })
  .strict();

/** Rutas de evaluación docente (§7.7, D-49, D-70). */
export function registrarRutasEvaluaciones(
  app: FastifyInstance,
  repo: RepositorioEvaluaciones,
): void {
  app.post('/api/v1/evaluaciones-docentes', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const datos = esquemaEvaluacion.parse(peticion.body ?? {});
    const evaluacion = await repo.crear(peticion.actor!.uid, datos);
    return respuesta.code(201).send(evaluacion);
  });

  app.get(
    '/api/v1/evaluaciones-docentes/resumen',
    { preHandler: [app.autenticar, app.requerirRoles('ADMIN_ACADEMICO')] },
    async () => repo.resumen(),
  );
}
