import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface ParticipanteAula {
  id: string;
  nombre: string;
  correo: string;
  rol: 'DOCENTE' | 'ESTUDIANTE';
  codigoInstitucional: string | null;
  fotoKey: string | null;
}

export interface ActividadProxima {
  actividadId: string;
  tipo: string;
  titulo: string;
  cierraEn: string | null;
  aulaId: string;
  aula: string;
  asignatura: string;
  codigo: string;
  entregada: boolean;
}

export interface RepositorioAulasSocial {
  participantes(uidFirebase: string, aulaId: string, esAdmin: boolean): Promise<ParticipanteAula[] | null>;
  proximas(uidFirebase: string): Promise<ActividadProxima[]>;
}

const iso = (valor: string | Date) =>
  (valor instanceof Date ? valor : new Date(valor)).toISOString();

/** Participantes del aula y próximas actividades del usuario (Fase 3, pantallas del estudiante). */
export function crearRepositorioAulasSocial(pool: Pool): RepositorioAulasSocial {
  return {
    async participantes(uidFirebase, aulaId, esAdmin) {
      const aula = await pool.query<{ id: string; grupo_id: string; docente_id: string | null }>(
        `SELECT au.id, au.grupo_id, g.docente_id
         FROM aula au JOIN grupo g ON g.id = au.grupo_id
         WHERE au.id = $1`,
        [aulaId],
      );
      const filaAula = aula.rows[0];
      if (!filaAula) return null;

      if (!esAdmin) {
        const acceso = await pool.query(
          `SELECT 1
           FROM aula au
           JOIN grupo g ON g.id = au.grupo_id
           JOIN usuario u ON u.uid_firebase = $2
           WHERE au.id = $1
             AND (g.docente_id = u.id
                  OR EXISTS (SELECT 1 FROM inscripcion i
                             WHERE i.grupo_id = g.id AND i.estudiante_id = u.id))`,
          [aulaId, uidFirebase],
        );
        if ((acceso.rowCount ?? 0) === 0) return null;
      }

      const docentes = await pool.query<{
        id: string;
        nombre: string;
        correo: string;
        codigo_institucional: string | null;
        foto_key: string | null;
      }>(
        `SELECT u.id, u.nombres || ' ' || u.apellidos AS nombre, u.correo,
                u.codigo_institucional, u.foto_key
         FROM aula au JOIN grupo g ON g.id = au.grupo_id
         JOIN usuario u ON u.id = g.docente_id
         WHERE au.id = $1`,
        [aulaId],
      );
      const estudiantes = await pool.query<{
        id: string;
        nombre: string;
        correo: string;
        codigo_institucional: string | null;
        foto_key: string | null;
      }>(
        `SELECT u.id, u.nombres || ' ' || u.apellidos AS nombre, u.correo,
                u.codigo_institucional, u.foto_key
         FROM aula au JOIN grupo g ON g.id = au.grupo_id
         JOIN inscripcion i ON i.grupo_id = g.id AND i.estado = 'ACTIVA'
         JOIN usuario u ON u.id = i.estudiante_id
         WHERE au.id = $1
         ORDER BY u.apellidos, u.nombres`,
        [aulaId],
      );

      return [
        ...docentes.rows.map((fila) => ({
          id: fila.id,
          nombre: fila.nombre,
          correo: fila.correo,
          rol: 'DOCENTE' as const,
          codigoInstitucional: fila.codigo_institucional,
          fotoKey: fila.foto_key,
        })),
        ...estudiantes.rows.map((fila) => ({
          id: fila.id,
          nombre: fila.nombre,
          correo: fila.correo,
          rol: 'ESTUDIANTE' as const,
          codigoInstitucional: fila.codigo_institucional,
          fotoKey: fila.foto_key,
        })),
      ];
    },

    async proximas(uidFirebase) {
      const resultado = await pool.query<{
        actividad_id: string;
        tipo: string;
        titulo: string;
        cierra_en: string | Date | null;
        aula_id: string;
        aula: string;
        asignatura: string;
        codigo: string;
        entregada: boolean;
      }>(
        `SELECT act.id AS actividad_id, act.tipo, act.titulo, act.cierra_en,
                au.id AS aula_id, au.nombre AS aula, asg.nombre AS asignatura, asg.codigo,
                EXISTS (
                  SELECT 1 FROM entrega e
                  JOIN usuario u2 ON u2.id = e.estudiante_id
                  WHERE e.actividad_id = act.id AND u2.uid_firebase = $1
                ) AS entregada
         FROM actividad act
         JOIN unidad un ON un.id = act.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         JOIN asignatura asg ON asg.id = g.asignatura_id
         WHERE act.cierra_en IS NOT NULL
           AND act.cierra_en >= now()
           AND EXISTS (SELECT 1 FROM inscripcion i
                       JOIN usuario u ON u.id = i.estudiante_id
                       WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA' AND u.uid_firebase = $1)
           -- Solo pendientes: una actividad ya entregada o un cuestionario ya respondido no se
           -- le recuerda al estudiante (corrección de la muestra).
           AND NOT EXISTS (
             SELECT 1 FROM entrega e
             JOIN usuario u2 ON u2.id = e.estudiante_id
             WHERE e.actividad_id = act.id AND u2.uid_firebase = $1
           )
           AND NOT EXISTS (
             SELECT 1 FROM intento_cuestionario ic
             JOIN usuario u3 ON u3.id = ic.estudiante_id
             WHERE ic.actividad_id = act.id AND u3.uid_firebase = $1
           )
         ORDER BY act.cierra_en NULLS LAST, act.titulo
         LIMIT 50`,
        [uidFirebase],
      );

      return resultado.rows.map((fila) => ({
        actividadId: fila.actividad_id,
        tipo: fila.tipo,
        titulo: fila.titulo,
        cierraEn: fila.cierra_en === null ? null : iso(fila.cierra_en),
        aulaId: fila.aula_id,
        aula: fila.aula,
        asignatura: fila.asignatura,
        codigo: fila.codigo,
        entregada: fila.entregada,
      }));
    },
  };
}

/** Rutas sociales del aula (§7.7, pantallas del estudiante). */
export function registrarRutasAulasSocial(
  app: FastifyInstance,
  repo: RepositorioAulasSocial,
): void {
  app.get('/api/v1/mis-actividades/proximas', { preHandler: app.autenticar }, async (peticion) =>
    repo.proximas(peticion.actor!.uid),
  );

  app.get('/api/v1/aulas/:id/participantes', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    const esAdmin = peticion.actor?.roles.includes('ADMIN_ACADEMICO') ?? false;
    const participantes = await repo.participantes(peticion.actor!.uid, id, esAdmin);
    if (!participantes) throw errores.noEncontrado('El aula no existe o no tienes acceso a ella');
    return participantes;
  });
}
