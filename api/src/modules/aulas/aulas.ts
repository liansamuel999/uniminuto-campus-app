import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';
import { resumirNotas, type ActividadCalificada, type CorteConActividades } from '../../lib/notas.js';

export interface AulaResumen {
  id: string;
  nombre: string;
  asignatura: string;
  codigo: string;
  periodo: string;
  grupo: string;
  docente: string | null;
  /** Rol del usuario dentro del aula: DOCENTE si dicta el grupo, ESTUDIANTE si está inscrito. */
  rolEnAula: 'DOCENTE' | 'ESTUDIANTE';
}

export interface ContenidoAula {
  id: string;
  tipo: string;
  titulo: string;
  descripcion: string | null;
  urlExterna: string | null;
  objetoKey: string | null;
}

export interface ActividadAula {
  id: string;
  tipo: string;
  titulo: string;
  instrucciones: string | null;
  cierraEn: string | null;
  peso: number;
  notaMaxima: number;
  corte: number;
}

export interface UnidadAula {
  id: string;
  numero: number;
  titulo: string;
  contenidos: ContenidoAula[];
  actividades: ActividadAula[];
}

export interface DetalleAula extends AulaResumen {
  unidades: UnidadAula[];
}

export interface NotaActividad {
  actividadId: string;
  titulo: string;
  peso: number;
  notaMaxima: number;
  nota: number | null;
  retroalimentacion: string | null;
  cierraEn: string | null;
}

export interface NotaAsignatura {
  inscripcionId: string;
  asignatura: string;
  codigo: string;
  cortes: Array<{
    numero: number;
    peso: number;
    nota: number | null;
    /** `true` cuando todas las actividades del corte ya cerraron (nota definitiva del corte). */
    cerrado: boolean;
    actividades: NotaActividad[];
  }>;
  /** Promedio ponderado del periodo; solo se publica cuando todos los cortes cerraron. */
  definitiva: number;
  /** `true` cuando la definitiva del periodo ya es la oficial (todos los cortes cerraron). */
  definitivaPublicada: boolean;
}

export interface RepositorioAulas {
  listar(uidFirebase: string, esAdmin: boolean): Promise<AulaResumen[]>;
  detalle(aulaId: string, uidFirebase: string, esAdmin: boolean): Promise<DetalleAula | null>;
  misNotas(uidFirebase: string, periodo?: string, aulaId?: string): Promise<NotaAsignatura[]>;
}

const ACCESO = `(
  $2::boolean = true
  OR g.docente_id = u.id
  OR EXISTS (SELECT 1 FROM inscripcion i WHERE i.grupo_id = g.id AND i.estudiante_id = u.id)
)`;

const BASE_AULA = `
  FROM aula a
  JOIN grupo g ON g.id = a.grupo_id
  JOIN asignatura asg ON asg.id = g.asignatura_id
  JOIN periodo p ON p.id = g.periodo_id
  JOIN usuario u ON u.uid_firebase = $1
  LEFT JOIN usuario d ON d.id = g.docente_id
`;

const CAMPOS_AULA = `
  SELECT a.id, a.nombre, asg.nombre AS asignatura, asg.codigo, p.codigo AS periodo,
         g.numero_grupo AS grupo, d.nombres || ' ' || d.apellidos AS docente,
         CASE WHEN g.docente_id = u.id THEN 'DOCENTE' ELSE 'ESTUDIANTE' END AS rol_en_aula
`;

export function crearRepositorioAulas(pool: Pool): RepositorioAulas {
  return {
    async listar(uidFirebase, esAdmin) {
      const resultado = await pool.query<{
        id: string;
        nombre: string;
        asignatura: string;
        codigo: string;
        periodo: string;
        grupo: string;
        docente: string | null;
        rol_en_aula: 'DOCENTE' | 'ESTUDIANTE';
      }>(
        `${CAMPOS_AULA} ${BASE_AULA}
         WHERE ${ACCESO}
         ORDER BY asg.nombre`,
        [uidFirebase, esAdmin],
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        nombre: fila.nombre,
        asignatura: fila.asignatura,
        codigo: fila.codigo,
        periodo: fila.periodo,
        grupo: fila.grupo,
        docente: fila.docente,
        rolEnAula: fila.rol_en_aula,
      }));
    },

    async detalle(aulaId, uidFirebase, esAdmin) {
      const aula = await pool.query<{
        id: string;
        nombre: string;
        asignatura: string;
        codigo: string;
        periodo: string;
        grupo: string;
        docente: string | null;
        rol_en_aula: 'DOCENTE' | 'ESTUDIANTE';
      }>(
        `${CAMPOS_AULA} ${BASE_AULA}
         WHERE a.id = $3 AND ${ACCESO}`,
        [uidFirebase, esAdmin, aulaId],
      );
      const filaAula = aula.rows[0];
      if (!filaAula) return null;

      const unidades = await pool.query<{ id: string; numero: number; titulo: string }>(
        'SELECT id, numero, titulo FROM unidad WHERE aula_id = $1 ORDER BY numero',
        [aulaId],
      );
      const contenidos = await pool.query<{
        id: string;
        unidad_id: string;
        tipo: string;
        titulo: string;
        descripcion: string | null;
        url_externa: string | null;
        objeto_key: string | null;
      }>(
        'SELECT id, unidad_id, tipo, titulo, descripcion, url_externa, objeto_key FROM contenido WHERE unidad_id = ANY($1::uuid[]) ORDER BY titulo',
        [unidades.rows.map((unidad) => unidad.id)],
      );
      const actividades = await pool.query<{
        id: string;
        unidad_id: string;
        tipo: string;
        titulo: string;
        instrucciones: string | null;
        cierra_en: string | Date | null;
        peso_porcentual: string;
        nota_maxima: string;
        numero: number;
        formatos_permitidos: string[] | null;
      }>(
        `SELECT a.id, a.unidad_id, a.tipo, a.titulo, a.instrucciones, a.cierra_en,
                a.peso_porcentual, a.nota_maxima, a.formatos_permitidos, c.numero
         FROM actividad a JOIN corte c ON c.id = a.corte_id
         WHERE a.unidad_id = ANY($1::uuid[]) ORDER BY a.titulo`,
        [unidades.rows.map((unidad) => unidad.id)],
      );

      return {
        id: filaAula.id,
        nombre: filaAula.nombre,
        asignatura: filaAula.asignatura,
        codigo: filaAula.codigo,
        periodo: filaAula.periodo,
        grupo: filaAula.grupo,
        docente: filaAula.docente,
        rolEnAula: filaAula.rol_en_aula,
        unidades: unidades.rows.map((unidad) => ({
          id: unidad.id,
          numero: unidad.numero,
          titulo: unidad.titulo,
          contenidos: contenidos.rows
            .filter((contenido) => contenido.unidad_id === unidad.id)
            .map((contenido) => ({
              id: contenido.id,
              tipo: contenido.tipo,
              titulo: contenido.titulo,
              descripcion: contenido.descripcion,
              urlExterna: contenido.url_externa,
              objetoKey: contenido.objeto_key,
            })),
          actividades: actividades.rows
            .filter((actividad) => actividad.unidad_id === unidad.id)
            .map((actividad) => ({
              id: actividad.id,
              tipo: actividad.tipo,
              titulo: actividad.titulo,
              instrucciones: actividad.instrucciones,
              formatosPermitidos: actividad.formatos_permitidos ?? [],
              cierraEn:
                actividad.cierra_en === null
                  ? null
                  : (actividad.cierra_en instanceof Date
                      ? actividad.cierra_en
                      : new Date(actividad.cierra_en)
                    ).toISOString(),
              peso: Number(actividad.peso_porcentual),
              notaMaxima: Number(actividad.nota_maxima),
              corte: actividad.numero,
            })),
        })),
      };
    },

    async misNotas(uidFirebase, periodo, aulaId) {
      const filas = await pool.query<{
        inscripcion_id: string;
        asignatura: string;
        codigo: string;
        corte_id: string;
        numero: number;
        corte_peso: string;
        actividad_id: string | null;
        titulo: string | null;
        act_peso: string | null;
        nota_maxima: string | null;
        nota: string | null;
        retroalimentacion: string | null;
        cierra_en: string | Date | null;
      }>(
        `SELECT i.id AS inscripcion_id, asg.nombre AS asignatura, asg.codigo,
                c.id AS corte_id, c.numero, c.peso_porcentual AS corte_peso,
                a.id AS actividad_id, a.titulo, a.peso_porcentual AS act_peso,
                a.nota_maxima, cal.nota, cal.retroalimentacion, a.cierra_en
         FROM inscripcion i
         JOIN grupo g ON g.id = i.grupo_id
         JOIN asignatura asg ON asg.id = g.asignatura_id
         JOIN periodo p ON p.id = g.periodo_id
         JOIN corte c ON c.grupo_id = g.id
         JOIN aula au ON au.grupo_id = g.id
         LEFT JOIN actividad a ON a.corte_id = c.id
         LEFT JOIN calificacion cal ON cal.actividad_id = a.id AND cal.inscripcion_id = i.id
         JOIN usuario u ON u.id = i.estudiante_id
         WHERE u.uid_firebase = $1
           AND ($2::text IS NULL OR p.codigo = $2)
           AND ($3::uuid IS NULL OR au.id = $3)
         ORDER BY asg.nombre, c.numero, a.titulo`,
        [uidFirebase, periodo ?? null, aulaId ?? null],
      );

      type Acumulada = {
        inscripcionId: string;
        asignatura: string;
        codigo: string;
        cortes: Map<string, { numero: number; peso: number; actividades: ActividadCalificada[] }>;
      };
      const porInscripcion = new Map<string, Acumulada>();

      for (const fila of filas.rows) {
        const actual =
          porInscripcion.get(fila.inscripcion_id) ??
          {
            inscripcionId: fila.inscripcion_id,
            asignatura: fila.asignatura,
            codigo: fila.codigo,
            cortes: new Map(),
          };
        porInscripcion.set(fila.inscripcion_id, actual);

        const corte =
          actual.cortes.get(fila.corte_id) ??
          { numero: fila.numero, peso: Number(fila.corte_peso), actividades: [] };
        actual.cortes.set(fila.corte_id, corte);

        if (fila.actividad_id) {
          corte.actividades.push({
            actividadId: fila.actividad_id,
            titulo: fila.titulo ?? '',
            peso: Number(fila.act_peso ?? 0),
            notaMaxima: Number(fila.nota_maxima ?? 5),
            nota: fila.nota === null ? null : Number(fila.nota),
            retroalimentacion: fila.retroalimentacion,
            cierraEn:
              fila.cierra_en === null
                ? null
                : (fila.cierra_en instanceof Date ? fila.cierra_en : new Date(fila.cierra_en)).toISOString(),
          });
        }
      }

      const ahora = Date.now();
      const corteCerrado = (actividades: ActividadCalificada[]): boolean =>
        actividades.length > 0 &&
        actividades.every(
          (actividad) =>
            actividad.cierraEn != null && new Date(actividad.cierraEn).getTime() <= ahora,
        );

      return [...porInscripcion.values()].map((acumulada) => {
        const cortes = [...acumulada.cortes.entries()]
          .map(([corteId, corte]) => ({
            corteId,
            numero: corte.numero,
            peso: corte.peso,
            actividades: corte.actividades,
          }))
          .sort((a, b) => a.numero - b.numero);

        const resumen = resumirNotas(cortes as CorteConActividades[]);
        const definitivaPublicada = cortes.length > 0 && cortes.every((corte) => corteCerrado(corte.actividades));
        return {
          inscripcionId: acumulada.inscripcionId,
          asignatura: acumulada.asignatura,
          codigo: acumulada.codigo,
          definitiva: resumen.definitiva,
          definitivaPublicada,
          cortes: cortes.map((corte, indice) => ({
            numero: corte.numero,
            peso: corte.peso,
            nota: resumen.cortes[indice]?.nota ?? null,
            cerrado: corteCerrado(corte.actividades),
            actividades: corte.actividades.map((actividad: ActividadCalificada) => ({
              actividadId: actividad.actividadId,
              titulo: actividad.titulo,
              peso: actividad.peso,
              notaMaxima: actividad.notaMaxima,
              nota: actividad.nota,
              retroalimentacion: actividad.retroalimentacion ?? null,
              cierraEn: actividad.cierraEn ?? null,
            })),
          })),
        };
      });
    },
  };
}

/** Rutas de Aulas Virtuales y notas del estudiante (§7.7). */
export function registrarRutasAulas(app: FastifyInstance, repo: RepositorioAulas): void {
  app.get('/api/v1/aulas', { preHandler: app.autenticar }, async (peticion) => {
    const esAdmin = peticion.actor?.roles.includes('ADMIN_ACADEMICO') ?? false;
    return repo.listar(peticion.actor!.uid, esAdmin);
  });

  app.get('/api/v1/aulas/:id', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    const esAdmin = peticion.actor?.roles.includes('ADMIN_ACADEMICO') ?? false;
    const detalle = await repo.detalle(id, peticion.actor!.uid, esAdmin);
    if (!detalle) throw errores.noEncontrado('El aula no existe o no tienes acceso a ella');
    return detalle;
  });

  app.get('/api/v1/mis-notas', { preHandler: app.autenticar }, async (peticion) => {
    const { periodo } = z
      .object({ periodo: z.string().regex(/^\d{4}-\d$/).optional() })
      .parse(peticion.query);
    return repo.misNotas(peticion.actor!.uid, periodo);
  });

  /** Notas del estudiante dentro de un curso concreto (botón «Calificaciones» del aula). */
  app.get('/api/v1/aulas/:id/mis-calificaciones', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    return repo.misNotas(peticion.actor!.uid, undefined, id);
  });
}
