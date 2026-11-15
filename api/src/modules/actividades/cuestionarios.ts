import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';
import { calificarIntento, type PreguntaCorregible } from '../../lib/cuestionarios.js';

export interface PreguntaParaEstudiante {
  id: string;
  enunciado: string;
  tipo: string;
  opciones: Array<{ id: string; texto: string }>;
}

/** Intento visto por el docente dueño del grupo (§6.4 paso 4). */
export interface IntentoListado {
  estudiante: string;
  puntaje: number;
  enviadoEn: string;
  respuestas: Record<string, string[]>;
}

export interface CuestionarioEstudiante {
  actividadId: string;
  titulo: string;
  instrucciones: string | null;
  notaMaxima: number;
  preguntas: PreguntaParaEstudiante[];
  yaRespondido: boolean;
}

export interface RepositorioCuestionarios {
  obtener(uidFirebase: string, actividadId: string): Promise<CuestionarioEstudiante>;
  responder(
    uidFirebase: string,
    actividadId: string,
    respuestas: Record<string, string[]>,
  ): Promise<{ puntaje: number; correctas: number; total: number }>;
  listarIntentos(uidDocente: string, actividadId: string): Promise<IntentoListado[]>;
}

export function crearRepositorioCuestionarios(pool: Pool): RepositorioCuestionarios {
  return {
    async obtener(uidFirebase, actividadId) {
      const actividad = await pool.query<{
        id: string;
        titulo: string;
        instrucciones: string | null;
        nota_maxima: string;
      }>(
        `SELECT a.id, a.titulo, a.instrucciones, a.nota_maxima
         FROM actividad a
         JOIN unidad un ON un.id = a.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         JOIN inscripcion i ON i.grupo_id = g.id
         JOIN usuario u ON u.id = i.estudiante_id
         WHERE a.id = $1 AND u.uid_firebase = $2 AND a.tipo = 'CUESTIONARIO'`,
        [actividadId, uidFirebase],
      );
      const fila = actividad.rows[0];
      if (!fila) throw errores.noEncontrado('El cuestionario no existe o no estás inscrito');

      const preguntas = await pool.query<{ id: string; enunciado: string; tipo: string }>(
        'SELECT id, enunciado, tipo FROM pregunta WHERE actividad_id = $1 ORDER BY orden',
        [actividadId],
      );
      const opciones = await pool.query<{ id: string; pregunta_id: string; texto: string }>(
        'SELECT id, pregunta_id, texto FROM opcion_respuesta WHERE pregunta_id = ANY($1::uuid[]) ORDER BY orden',
        [preguntas.rows.map((pregunta) => pregunta.id)],
      );
      const intento = await pool.query(
        `SELECT 1 FROM intento_cuestionario i JOIN usuario u ON u.id = i.estudiante_id
         WHERE i.actividad_id = $1 AND u.uid_firebase = $2`,
        [actividadId, uidFirebase],
      );

      return {
        actividadId: fila.id,
        titulo: fila.titulo,
        instrucciones: fila.instrucciones,
        notaMaxima: Number(fila.nota_maxima),
        yaRespondido: (intento.rowCount ?? 0) > 0,
        preguntas: preguntas.rows.map((pregunta) => ({
          id: pregunta.id,
          enunciado: pregunta.enunciado,
          tipo: pregunta.tipo,
          opciones: opciones.rows
            .filter((opcion) => opcion.pregunta_id === pregunta.id)
            .map((opcion) => ({ id: opcion.id, texto: opcion.texto })),
        })),
      };
    },

    async responder(uidFirebase, actividadId, respuestas) {
      return withTx(pool, async (cliente) => {
        const contexto = await cliente.query<{
          nota_maxima: string;
          corte_id: string;
          inscripcion_id: string;
        }>(
          `SELECT a.nota_maxima, a.corte_id, i.id AS inscripcion_id
           FROM actividad a
           JOIN unidad un ON un.id = a.unidad_id
           JOIN aula au ON au.id = un.aula_id
           JOIN grupo g ON g.id = au.grupo_id
           JOIN inscripcion i ON i.grupo_id = g.id
           JOIN usuario u ON u.id = i.estudiante_id
           WHERE a.id = $1 AND u.uid_firebase = $2 AND a.tipo = 'CUESTIONARIO'`,
          [actividadId, uidFirebase],
        );
        const fila = contexto.rows[0];
        if (!fila) throw errores.noEncontrado('El cuestionario no existe o no estás inscrito');

        const preguntas = await cliente.query<{ id: string }>(
          'SELECT id FROM pregunta WHERE actividad_id = $1 ORDER BY orden',
          [actividadId],
        );
        const opciones = await cliente.query<{ id: string; pregunta_id: string; es_correcta: boolean }>(
          'SELECT id, pregunta_id, es_correcta FROM opcion_respuesta WHERE pregunta_id = ANY($1::uuid[])',
          [preguntas.rows.map((pregunta) => pregunta.id)],
        );
        const corregibles: PreguntaCorregible[] = preguntas.rows.map((pregunta) => ({
          id: pregunta.id,
          opciones: opciones.rows
            .filter((opcion) => opcion.pregunta_id === pregunta.id)
            .map((opcion) => ({ id: opcion.id, esCorrecta: opcion.es_correcta })),
        }));

        const resultado = calificarIntento(corregibles, respuestas, Number(fila.nota_maxima));

        const intento = await cliente.query(
          `INSERT INTO intento_cuestionario (actividad_id, estudiante_id, respuestas, puntaje)
           SELECT $1, i.estudiante_id, $2::jsonb, $3 FROM inscripcion i WHERE i.id = $4
           ON CONFLICT (actividad_id, estudiante_id) DO NOTHING
           RETURNING id`,
          [actividadId, JSON.stringify(respuestas), resultado.puntaje, fila.inscripcion_id],
        );
        if (!intento.rows[0]) throw errores.conflicto('Ya respondiste este cuestionario');

        await cliente.query(
          `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
           VALUES ($1, $2, $3, 'Autocalificado por el cuestionario')
           ON CONFLICT (actividad_id, inscripcion_id)
           DO UPDATE SET nota = EXCLUDED.nota, calificada_en = now()`,
          [actividadId, fila.inscripcion_id, resultado.puntaje],
        );

        // Recálculo de la nota del corte en la misma transacción (§6.4).
        await cliente.query(
          `INSERT INTO nota_corte (inscripcion_id, corte_id, nota_calculada)
           SELECT $1, $2,
                  ROUND(SUM(c.nota * a.peso_porcentual) / NULLIF(SUM(a.peso_porcentual), 0), 2)
           FROM calificacion c JOIN actividad a ON a.id = c.actividad_id
           WHERE c.inscripcion_id = $1 AND a.corte_id = $2
           ON CONFLICT (inscripcion_id, corte_id)
           DO UPDATE SET nota_calculada = EXCLUDED.nota_calculada, actualizada_en = now()`,
          [fila.inscripcion_id, fila.corte_id],
        );

        return resultado;
      });
    },

    async listarIntentos(uidDocente, actividadId) {
      const acceso = await pool.query<{ id: string }>(
        `SELECT a.id FROM actividad a
         JOIN unidad un ON un.id = a.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         JOIN usuario u ON u.id = g.docente_id
         WHERE a.id = $1 AND u.uid_firebase = $2 AND a.tipo = 'CUESTIONARIO'`,
        [actividadId, uidDocente],
      );
      if (!acceso.rows[0]) {
        throw errores.noEncontrado('El cuestionario no existe o no es de tus grupos');
      }

      const intentos = await pool.query<{
        estudiante: string;
        puntaje: string;
        enviado_en: string | Date;
        respuestas: unknown;
      }>(
        `SELECT u.nombres || ' ' || u.apellidos AS estudiante, i.puntaje, i.enviado_en, i.respuestas
         FROM intento_cuestionario i JOIN usuario u ON u.id = i.estudiante_id
         WHERE i.actividad_id = $1 ORDER BY i.enviado_en`,
        [actividadId],
      );

      return intentos.rows.map((fila) => ({
        estudiante: fila.estudiante,
        puntaje: Number(fila.puntaje),
        enviadoEn: (fila.enviado_en instanceof Date
          ? fila.enviado_en
          : new Date(fila.enviado_en)
        ).toISOString(),
        respuestas:
          fila.respuestas && typeof fila.respuestas === 'object'
            ? (fila.respuestas as Record<string, string[]>)
            : {},
      }));
    },
  };
}

const esquemaRespuestas = z
  .object({
    respuestas: z.record(z.string().uuid(), z.array(z.string().uuid()).max(10)),
  })
  .strict();

export function registrarRutasCuestionarios(app: FastifyInstance, repo: RepositorioCuestionarios): void {
  app.get('/api/v1/cuestionarios/:id', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    return repo.obtener(peticion.actor!.uid, id);
  });

  app.post('/api/v1/cuestionarios/:id/intentos', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    const { respuestas } = esquemaRespuestas.parse(peticion.body ?? {});
    const resultado = await repo.responder(peticion.actor!.uid, id, respuestas);
    return respuesta.code(201).send(resultado);
  });

  // Revisión de intentos por el docente dueño del grupo (§6.4 paso 4).
  app.get('/api/v1/cuestionarios/:id/intentos', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    return repo.listarIntentos(peticion.actor!.uid, id);
  });
}
