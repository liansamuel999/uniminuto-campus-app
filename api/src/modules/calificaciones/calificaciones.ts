import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';
import { notificarAlUsuario } from '../../lib/notificaciones.js';

export interface FilaCalificacion {
  inscripcionId: string;
  estudiante: string;
  actividadId: string;
  titulo: string;
  notaMaxima: number;
  nota: number | null;
  retroalimentacion: string | null;
}

export interface RepositorioCalificaciones {
  calificar(
    uidDocente: string,
    datos: { actividadId: string; inscripcionId: string; nota: number; retroalimentacion?: string },
  ): Promise<{ nota: number; notaCorte: number | null }>;
  listar(uid: string, aulaId: string): Promise<FilaCalificacion[]>;
}

export function crearRepositorioCalificaciones(pool: Pool): RepositorioCalificaciones {
  return {
    async calificar(uidDocente, datos) {
      const resultadoTx = await withTx(pool, async (cliente) => {
        const contexto = await cliente.query<{
          nota_maxima: string;
          corte_id: string;
          docente_id: string;
          titulo: string;
        }>(
          `SELECT a.nota_maxima, a.corte_id, g.docente_id, a.titulo
           FROM actividad a
           JOIN unidad un ON un.id = a.unidad_id
           JOIN aula au ON au.id = un.aula_id
           JOIN grupo g ON g.id = au.grupo_id
           JOIN usuario u ON u.id = g.docente_id
           WHERE a.id = $1 AND u.uid_firebase = $2`,
          [datos.actividadId, uidDocente],
        );
        const fila = contexto.rows[0];
        if (!fila) throw errores.prohibido('Solo el docente del grupo puede calificar esta actividad');
        const tituloActividad = fila.titulo;

        const notaMaxima = Number(fila.nota_maxima);
        if (datos.nota < 0 || datos.nota > notaMaxima) {
          throw errores.datosInvalidos(`La nota debe estar entre 0 y ${notaMaxima}`);
        }

        const inscripcion = await cliente.query<{
          id: string;
          docente_id: string;
          estudiante_uid: string;
        }>(
          `SELECT i.id, g.docente_id, u.uid_firebase AS estudiante_uid
           FROM inscripcion i
           JOIN grupo g ON g.id = i.grupo_id
           JOIN usuario u ON u.id = i.estudiante_id
           JOIN unidad un ON un.id = (SELECT unidad_id FROM actividad WHERE id = $2)
           JOIN aula au ON au.id = un.aula_id
           WHERE i.id = $1 AND au.grupo_id = g.id`,
          [datos.inscripcionId, datos.actividadId],
        );
        if (!inscripcion.rows[0]) {
          throw errores.datosInvalidos('La inscripción no pertenece al grupo de la actividad');
        }
        const estudianteUid = inscripcion.rows[0].estudiante_uid;

        const calificacion = await cliente.query<{ id: string }>(
          `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion, calificada_por)
           VALUES ($1, $2, $3, $4, (SELECT id FROM usuario WHERE uid_firebase = $5))
           ON CONFLICT (actividad_id, inscripcion_id)
           DO UPDATE SET nota = EXCLUDED.nota, retroalimentacion = EXCLUDED.retroalimentacion,
                         calificada_en = now(), calificada_por = EXCLUDED.calificada_por
           RETURNING id`,
          [datos.actividadId, datos.inscripcionId, datos.nota, datos.retroalimentacion ?? null, uidDocente],
        );
        const calificacionId = calificacion.rows[0]!.id;

        const corte = await cliente.query<{ nota_calculada: string | null }>(
          `INSERT INTO nota_corte (inscripcion_id, corte_id, nota_calculada)
           SELECT $1, $2,
                  ROUND(SUM(c.nota * a.peso_porcentual) / NULLIF(SUM(a.peso_porcentual), 0), 2)
           FROM calificacion c JOIN actividad a ON a.id = c.actividad_id
           WHERE c.inscripcion_id = $1 AND a.corte_id = $2
           ON CONFLICT (inscripcion_id, corte_id)
           DO UPDATE SET nota_calculada = EXCLUDED.nota_calculada, actualizada_en = now()
           RETURNING nota_calculada`,
          [datos.inscripcionId, fila.corte_id],
        );

        await cliente.query(
          `INSERT INTO evento_auditoria (actor_id, accion, recurso, resultado)
           VALUES ((SELECT id FROM usuario WHERE uid_firebase = $1), 'CAMBIO_NOTA', $2, 'OK')`,
          [uidDocente, `calificacion:${calificacionId}`],
        );

        return {
          nota: datos.nota,
          notaCorte:
            corte.rows[0]?.nota_calculada == null ? null : Number(corte.rows[0].nota_calculada),
          estudianteUid,
          titulo: tituloActividad,
        };
      });

      // Aviso al estudiante fuera de la transacción SQL: Firestore no participa de ella (§6.4).
      // Si Firebase no está disponible, la calificación ya quedó registrada y no se pierde.
      await notificarAlUsuario({
        uid: resultadoTx.estudianteUid,
        titulo: 'Nueva calificación',
        cuerpo: `Tu actividad «${resultadoTx.titulo}» fue calificada con ${resultadoTx.nota}.`,
        tipo: 'NOTA',
      });

      return { nota: resultadoTx.nota, notaCorte: resultadoTx.notaCorte };
    },

    async listar(uid, aulaId) {
      const acceso = await pool.query<{ id: string }>(
        `SELECT a.id FROM aula a
         JOIN grupo g ON g.id = a.grupo_id
         JOIN usuario u ON u.id = g.docente_id
         WHERE a.id = $1 AND u.uid_firebase = $2`,
        [aulaId, uid],
      );
      if (!acceso.rows[0]) throw errores.noEncontrado('El aula no existe o no es de tus grupos');

      const resultado = await pool.query<{
        inscripcion_id: string;
        estudiante: string;
        actividad_id: string;
        titulo: string;
        nota_maxima: string;
        nota: string | null;
        retroalimentacion: string | null;
      }>(
        `SELECT DISTINCT i.id AS inscripcion_id, u.nombres || ' ' || u.apellidos AS estudiante,
                a.id AS actividad_id, a.titulo, a.nota_maxima, c.nota, c.retroalimentacion
         FROM inscripcion i
         JOIN usuario u ON u.id = i.estudiante_id
         JOIN grupo g ON g.id = i.grupo_id
         JOIN unidad un ON un.id IN (SELECT id FROM unidad WHERE aula_id = $1)
         JOIN actividad a ON a.unidad_id = un.id
         LEFT JOIN calificacion c ON c.actividad_id = a.id AND c.inscripcion_id = i.id
         WHERE g.id = (SELECT grupo_id FROM aula WHERE id = $1)
         ORDER BY a.titulo, estudiante`,
        [aulaId],
      );

      return resultado.rows.map((fila) => ({
        inscripcionId: fila.inscripcion_id,
        estudiante: fila.estudiante,
        actividadId: fila.actividad_id,
        titulo: fila.titulo,
        notaMaxima: Number(fila.nota_maxima),
        nota: fila.nota === null ? null : Number(fila.nota),
        retroalimentacion: fila.retroalimentacion,
      }));
    },
  };
}

const esquemaCalificacion = z
  .object({
    actividadId: z.string().uuid(),
    inscripcionId: z.string().uuid(),
    nota: z.number().min(0).max(5),
    retroalimentacion: z.string().trim().max(1000).optional(),
  })
  .strict();

export function registrarRutasCalificaciones(app: FastifyInstance, repo: RepositorioCalificaciones): void {
  app.put('/api/v1/calificaciones', { preHandler: app.autenticar }, async (peticion) => {
    const datos = esquemaCalificacion.parse(peticion.body ?? {});
    return repo.calificar(peticion.actor!.uid, datos);
  });

  app.get('/api/v1/aulas/:id/calificaciones', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    return repo.listar(peticion.actor!.uid, id);
  });
}
