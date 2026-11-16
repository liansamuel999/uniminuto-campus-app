import type { FastifyInstance } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';

import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';
import { eliminarIndiceForo, sincronizarIndiceForo } from '../../lib/indices_foros.js';

export interface RepositorioAulasDocente {
  actualizarAula(
    uid: string,
    aulaId: string,
    datos: { nombre?: string; descripcion?: string },
    esAdmin?: boolean,
  ): Promise<boolean>;
  crearUnidad(uid: string, aulaId: string, datos: { titulo: string; numero?: number }): Promise<{ id: string }>;
  actualizarUnidad(uid: string, unidadId: string, datos: { titulo?: string; numero?: number }): Promise<boolean>;
  eliminarUnidad(uid: string, unidadId: string): Promise<boolean>;
  crearContenido(
    uid: string,
    unidadId: string,
    datos: {
      tipo: string;
      titulo: string;
      descripcion?: string;
      objetoKey?: string;
      urlExterna?: string;
      mime?: string;
      tamano?: number;
    },
  ): Promise<{ id: string }>;
  actualizarContenido(
    uid: string,
    contenidoId: string,
    datos: {
      tipo?: string;
      titulo?: string;
      descripcion?: string;
      objetoKey?: string;
      urlExterna?: string;
      mime?: string;
      tamano?: number;
    },
  ): Promise<boolean>;
  eliminarContenido(uid: string, contenidoId: string): Promise<boolean>;
  crearActividad(
    uid: string,
    unidadId: string,
    datos: {
      tipo: string;
      titulo: string;
      instrucciones?: string;
      cierraEn?: Date;
      corte: number;
      peso: number;
      notaMaxima?: number;
      formatosPermitidos?: string[];
      revisionPermitida?: boolean;
    },
  ): Promise<{ id: string }>;
  actualizarActividad(
    uid: string,
    actividadId: string,
    datos: {
      titulo?: string;
      instrucciones?: string;
      cierraEn?: Date;
      peso?: number;
      notaMaxima?: number;
      formatosPermitidos?: string[];
      revisionPermitida?: boolean;
    },
  ): Promise<boolean>;
  eliminarActividad(uid: string, actividadId: string): Promise<boolean>;
  /** Actividad con sus preguntas y respuestas correctas, para el editor del docente. */
  detalleEditor(uid: string, actividadId: string): Promise<{
    id: string;
    tipo: string;
    titulo: string;
    instrucciones: string | null;
    cierraEn: string | null;
    corte: number;
    peso: number;
    notaMaxima: number;
    formatosPermitidos: string[];
    revisionPermitida: boolean;
    preguntas: Array<{
      id: string;
      enunciado: string;
      tipo: string;
      opciones: Array<{ id: string; texto: string; esCorrecta: boolean }>;
    }>;
    recursos: Array<{
      id: string;
      objetoKey: string;
      nombre: string;
      mime: string | null;
      tamano: number | null;
    }>;
  }>;
  /** Reemplaza todas las preguntas/opciones del cuestionario (editor completo). */
  reemplazarCuestionario(
    uid: string,
    actividadId: string,
    datos: {
      revisionPermitida: boolean;
      preguntas: Array<{
        enunciado: string;
        tipo?: string;
        opciones: Array<{ texto: string; esCorrecta: boolean }>;
      }>;
    },
  ): Promise<boolean>;
  /** Archivos/materiales propios de la actividad (independientes de los contenidos del aula). */
  agregarRecurso(
    uid: string,
    actividadId: string,
    datos: { objetoKey: string; nombre: string; mime?: string; tamano?: number },
  ): Promise<{ id: string }>;
  eliminarRecurso(uid: string, recursoId: string): Promise<boolean>;
}

interface AulaDeGrupo {
  aulaId: string;
  grupoId: string;
  docenteId: string | null;
}

async function aulaPorUid(cliente: Pick<Pool, 'query'>, uid: string, aulaId: string): Promise<AulaDeGrupo | null> {
  const resultado = await cliente.query<{ aula_id: string; grupo_id: string; docente_id: string | null }>(
    `SELECT a.id AS aula_id, g.id AS grupo_id, g.docente_id
     FROM aula a JOIN grupo g ON g.id = a.grupo_id
     JOIN usuario u ON u.uid_firebase = $2
     WHERE a.id = $1 AND g.docente_id = u.id`,
    [aulaId, uid],
  );
  const fila = resultado.rows[0];
  return fila ? { aulaId: fila.aula_id, grupoId: fila.grupo_id, docenteId: fila.docente_id } : null;
}

async function aulaDeUnidad(cliente: Pick<Pool, 'query'>, uid: string, unidadId: string) {
  const resultado = await cliente.query<{ aula_id: string; grupo_id: string; docente_id: string | null }>(
    `SELECT a.id AS aula_id, g.id AS grupo_id, g.docente_id
     FROM unidad un JOIN aula a ON a.id = un.aula_id
     JOIN grupo g ON g.id = a.grupo_id
     JOIN usuario u ON u.uid_firebase = $2
     WHERE un.id = $1 AND g.docente_id = u.id`,
    [unidadId, uid],
  );
  return resultado.rows[0] ?? null;
}

async function aulaDeContenido(cliente: Pick<Pool, 'query'>, uid: string, contenidoId: string) {
  const resultado = await cliente.query<{ aula_id: string; grupo_id: string; docente_id: string | null }>(
    `SELECT a.id AS aula_id, g.id AS grupo_id, g.docente_id
     FROM contenido co JOIN unidad un ON un.id = co.unidad_id
     JOIN aula a ON a.id = un.aula_id
     JOIN grupo g ON g.id = a.grupo_id
     JOIN usuario u ON u.uid_firebase = $2
     WHERE co.id = $1 AND g.docente_id = u.id`,
    [contenidoId, uid],
  );
  return resultado.rows[0] ?? null;
}

async function aulaDeActividad(cliente: Pick<Pool, 'query'>, uid: string, actividadId: string) {
  const resultado = await cliente.query<{
    aula_id: string;
    grupo_id: string;
    docente_id: string | null;
    corte_id: string;
    tipo: string;
  }>(
    `SELECT a.id AS aula_id, g.id AS grupo_id, g.docente_id, act.corte_id, act.tipo
     FROM actividad act JOIN unidad un ON un.id = act.unidad_id
     JOIN aula a ON a.id = un.aula_id
     JOIN grupo g ON g.id = a.grupo_id
     JOIN usuario u ON u.uid_firebase = $2
     WHERE act.id = $1 AND g.docente_id = u.id`,
    [actividadId, uid],
  );
  return resultado.rows[0] ?? null;
}

async function validarPesoCorte(
  cliente: PoolClient,
  corteId: string,
  peso: number,
  excluirActividadId?: string,
): Promise<void> {
  const suma = await cliente.query<{ total: string }>(
    `SELECT COALESCE(SUM(peso_porcentual), 0) AS total FROM actividad
     WHERE corte_id = $1 AND ($2::uuid IS NULL OR id <> $2)`,
    [corteId, excluirActividadId ?? null],
  );
  const acumulado = Number(suma.rows[0]?.total ?? 0);
  if (acumulado + peso > 100) {
    throw errores.datosInvalidos(
      `La actividad excede el 100 % del corte (ya hay ${acumulado.toFixed(2)} % asignado)`,
    );
  }
}

/** Edición del aula por el docente dueño del grupo (§5, Fase 3/6). */
export function crearRepositorioAulasDocente(pool: Pool): RepositorioAulasDocente {
  return {
    async actualizarAula(uid, aulaId, datos, esAdmin = false) {
      if (esAdmin) {
        const existe = await pool.query('SELECT 1 FROM aula WHERE id = $1', [aulaId]);
        if (!existe.rows[0]) throw errores.noEncontrado('El aula virtual no existe');
      } else {
        const aula = await aulaPorUid(pool, uid, aulaId);
        if (!aula) throw errores.prohibido('Solo el docente del aula puede editarla');
      }
      await pool.query(
        `UPDATE aula SET nombre = COALESCE($2, nombre), descripcion = COALESCE($3, descripcion)
         WHERE id = $1`,
        [aulaId, datos.nombre ?? null, datos.descripcion ?? null],
      );
      return true;
    },

    async crearUnidad(uid, aulaId, datos) {
      const aula = await aulaPorUid(pool, uid, aulaId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede crear unidades');
      const numero =
        datos.numero ??
        (
          await pool.query<{ siguiente: number }>(
            'SELECT COALESCE(MAX(numero), 0) + 1 AS siguiente FROM unidad WHERE aula_id = $1',
            [aulaId],
          )
        ).rows[0]!.siguiente;
      const resultado = await pool.query<{ id: string }>(
        `INSERT INTO unidad (aula_id, numero, titulo) VALUES ($1, $2, $3) RETURNING id`,
        [aulaId, numero, datos.titulo],
      );
      return { id: resultado.rows[0]!.id };
    },

    async actualizarUnidad(uid, unidadId, datos) {
      const aula = await aulaDeUnidad(pool, uid, unidadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede editar sus unidades');
      await pool.query(
        `UPDATE unidad SET titulo = COALESCE($2, titulo), numero = COALESCE($3, numero) WHERE id = $1`,
        [unidadId, datos.titulo ?? null, datos.numero ?? null],
      );
      return true;
    },

    async eliminarUnidad(uid, unidadId) {
      const aula = await aulaDeUnidad(pool, uid, unidadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede eliminar sus unidades');
      try {
        const resultado = await pool.query('DELETE FROM unidad WHERE id = $1', [unidadId]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if ((error as { code?: string }).code === '23503') {
          throw errores.conflicto('La unidad tiene actividades calificadas o entregas asociadas');
        }
        throw error;
      }
    },

    async crearContenido(uid, unidadId, datos) {
      const aula = await aulaDeUnidad(pool, uid, unidadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede publicar contenidos');
      const resultado = await pool.query<{ id: string }>(
        `INSERT INTO contenido (unidad_id, tipo, titulo, descripcion, objeto_key, url_externa, mime, tamano)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
        [
          unidadId,
          datos.tipo,
          datos.titulo,
          datos.descripcion ?? null,
          datos.objetoKey ?? null,
          datos.urlExterna ?? null,
          datos.mime ?? null,
          datos.tamano ?? null,
        ],
      );
      return { id: resultado.rows[0]!.id };
    },

    async actualizarContenido(uid, contenidoId, datos) {
      const aula = await aulaDeContenido(pool, uid, contenidoId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede editar sus contenidos');
      await pool.query(
        `UPDATE contenido SET
           tipo = COALESCE($8, tipo),
           titulo = COALESCE($2, titulo),
           descripcion = COALESCE($3, descripcion),
           objeto_key = COALESCE($4, objeto_key),
           url_externa = COALESCE($5, url_externa),
           mime = COALESCE($6, mime),
           tamano = COALESCE($7, tamano)
         WHERE id = $1`,
        [
          contenidoId,
          datos.titulo ?? null,
          datos.descripcion ?? null,
          datos.objetoKey ?? null,
          datos.urlExterna ?? null,
          datos.mime ?? null,
          datos.tamano ?? null,
          datos.tipo ?? null,
        ],
      );
      return true;
    },

    async eliminarContenido(uid, contenidoId) {
      const aula = await aulaDeContenido(pool, uid, contenidoId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede eliminar sus contenidos');
      const resultado = await pool.query('DELETE FROM contenido WHERE id = $1', [contenidoId]);
      return (resultado.rowCount ?? 0) > 0;
    },

    async crearActividad(uid, unidadId, datos) {
      const aula = await aulaDeUnidad(pool, uid, unidadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede crear actividades');

      const creada = await withTx(pool, async (cliente) => {
        const corte = await cliente.query<{ id: string }>(
          'SELECT id FROM corte WHERE grupo_id = $1 AND numero = $2',
          [aula.grupo_id, datos.corte],
        );
        const corteId = corte.rows[0]?.id;
        if (!corteId) throw errores.datosInvalidos('El corte indicado no existe en el grupo');

        await validarPesoCorte(cliente, corteId, datos.peso);

        const resultado = await cliente.query<{ id: string }>(
          `INSERT INTO actividad (unidad_id, tipo, titulo, instrucciones, cierra_en, corte_id, peso_porcentual, nota_maxima, formatos_permitidos, revision_permitida)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::text[], $10) RETURNING id`,
          [
            unidadId,
            datos.tipo,
            datos.titulo,
            datos.instrucciones ?? null,
            datos.cierraEn ?? null,
            corteId,
            datos.peso,
            datos.notaMaxima ?? 5,
            datos.formatosPermitidos ?? null,
            datos.revisionPermitida ?? false,
          ],
        );
        const actividadId = resultado.rows[0]!.id;

        // En la muestra un cuestionario nuevo nace con 3 preguntas genéricas para que el flujo
        // (intento único y autocalificación) funcione sin un editor de preguntas completo.
        if (datos.tipo === 'CUESTIONARIO') {
          for (let orden = 1; orden <= 3; orden += 1) {
            const pregunta = await cliente.query<{ id: string }>(
              'INSERT INTO pregunta (actividad_id, enunciado, orden) VALUES ($1, $2, $3) RETURNING id',
              [actividadId, `Pregunta ${orden} del cuestionario`, orden],
            );
            const preguntaId = pregunta.rows[0]!.id;
            for (const [indice, texto] of ['Opción A', 'Opción B', 'Opción C'].entries()) {
              await cliente.query(
                'INSERT INTO opcion_respuesta (pregunta_id, texto, es_correcta, orden) VALUES ($1, $2, $3, $4)',
                [preguntaId, texto, indice === 0, indice + 1],
              );
            }
          }
        }

        return { id: actividadId };
      });

      if (datos.tipo === 'FORO') {
        await sincronizarIndiceForo(pool, creada.id, aula.aula_id);
      }
      return creada;
    },

    async actualizarActividad(uid, actividadId, datos) {
      const aula = await aulaDeActividad(pool, uid, actividadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede editar sus actividades');

      return withTx(pool, async (cliente) => {
        if (datos.peso !== undefined) {
          await validarPesoCorte(cliente, aula.corte_id, datos.peso, actividadId);
        }
        await cliente.query(
          `UPDATE actividad SET
             titulo = COALESCE($2, titulo),
             instrucciones = COALESCE($3, instrucciones),
             cierra_en = COALESCE($4, cierra_en),
             peso_porcentual = COALESCE($5, peso_porcentual),
             nota_maxima = COALESCE($6, nota_maxima),
             formatos_permitidos = COALESCE($7::text[], formatos_permitidos),
             revision_permitida = COALESCE($8, revision_permitida)
           WHERE id = $1`,
          [
            actividadId,
            datos.titulo ?? null,
            datos.instrucciones ?? null,
            datos.cierraEn ?? null,
            datos.peso ?? null,
            datos.notaMaxima ?? null,
            datos.formatosPermitidos ?? null,
            datos.revisionPermitida ?? null,
          ],
        );
        return true;
      });
    },

    async eliminarActividad(uid, actividadId) {
      const aula = await aulaDeActividad(pool, uid, actividadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede eliminar sus actividades');
      try {
        const resultado = await pool.query('DELETE FROM actividad WHERE id = $1', [actividadId]);
        if (aula.tipo === 'FORO') await eliminarIndiceForo(actividadId);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if ((error as { code?: string }).code === '23503') {
          throw errores.conflicto('La actividad ya tiene entregas, intentos o calificaciones');
        }
        throw error;
      }
    },

    async detalleEditor(uid, actividadId) {
      const aula = await aulaDeActividad(pool, uid, actividadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede editar sus actividades');

      const actividad = await pool.query<{
        id: string;
        tipo: string;
        titulo: string;
        instrucciones: string | null;
        cierra_en: string | Date | null;
        corte: number;
        peso_porcentual: string;
        nota_maxima: string;
        formatos_permitidos: string[] | null;
        revision_permitida: boolean;
      }>(
        `SELECT act.id, act.tipo, act.titulo, act.instrucciones, act.cierra_en,
                c.numero AS corte, act.peso_porcentual, act.nota_maxima,
                act.formatos_permitidos, act.revision_permitida
         FROM actividad act JOIN corte c ON c.id = act.corte_id
         WHERE act.id = $1`,
        [actividadId],
      );
      const fila = actividad.rows[0]!;

      const preguntas = await pool.query<{ id: string; enunciado: string; tipo: string }>(
        'SELECT id, enunciado, tipo FROM pregunta WHERE actividad_id = $1 ORDER BY orden',
        [actividadId],
      );
      const opciones = await pool.query<{
        id: string;
        pregunta_id: string;
        texto: string;
        es_correcta: boolean;
      }>(
        'SELECT id, pregunta_id, texto, es_correcta FROM opcion_respuesta WHERE pregunta_id = ANY($1::uuid[]) ORDER BY orden',
        [preguntas.rows.map((pregunta) => pregunta.id)],
      );

      const recursos = await pool.query<{
        id: string;
        objeto_key: string;
        nombre: string;
        mime: string | null;
        tamano: string | null;
      }>(
        `SELECT id, objeto_key, nombre, mime, tamano FROM actividad_recurso
         WHERE actividad_id = $1 ORDER BY creado_en`,
        [actividadId],
      );

      return {
        id: fila.id,
        tipo: fila.tipo,
        titulo: fila.titulo,
        instrucciones: fila.instrucciones,
        cierraEn: fila.cierra_en ? new Date(fila.cierra_en).toISOString() : null,
        corte: fila.corte,
        peso: Number(fila.peso_porcentual),
        notaMaxima: Number(fila.nota_maxima),
        formatosPermitidos: fila.formatos_permitidos ?? [],
        revisionPermitida: fila.revision_permitida,
        preguntas: preguntas.rows.map((pregunta) => ({
          id: pregunta.id,
          enunciado: pregunta.enunciado,
          tipo: pregunta.tipo,
          opciones: opciones.rows
            .filter((opcion) => opcion.pregunta_id === pregunta.id)
            .map((opcion) => ({
              id: opcion.id,
              texto: opcion.texto,
              esCorrecta: opcion.es_correcta,
            })),
        })),
        recursos: recursos.rows.map((recurso) => ({
          id: recurso.id,
          objetoKey: recurso.objeto_key,
          nombre: recurso.nombre,
          mime: recurso.mime,
          tamano: recurso.tamano === null ? null : Number(recurso.tamano),
        })),
      };
    },

    async reemplazarCuestionario(uid, actividadId, datos) {
      const aula = await aulaDeActividad(pool, uid, actividadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede editar sus cuestionarios');
      if (aula.tipo !== 'CUESTIONARIO') throw errores.datosInvalidos('La actividad no es un cuestionario');
      for (const pregunta of datos.preguntas) {
        if (!pregunta.opciones.some((opcion) => opcion.esCorrecta)) {
          throw errores.datosInvalidos('Cada pregunta debe tener al menos una respuesta correcta');
        }
      }

      return withTx(pool, async (cliente) => {
        await cliente.query('UPDATE actividad SET revision_permitida = $2 WHERE id = $1', [
          actividadId,
          datos.revisionPermitida,
        ]);
        await cliente.query('DELETE FROM pregunta WHERE actividad_id = $1', [actividadId]);
        for (const [indice, pregunta] of datos.preguntas.entries()) {
          const creada = await cliente.query<{ id: string }>(
            'INSERT INTO pregunta (actividad_id, enunciado, tipo, orden) VALUES ($1, $2, $3, $4) RETURNING id',
            [actividadId, pregunta.enunciado, pregunta.tipo ?? 'UNICA', indice + 1],
          );
          const preguntaId = creada.rows[0]!.id;
          for (const [orden, opcion] of pregunta.opciones.entries()) {
            await cliente.query(
              'INSERT INTO opcion_respuesta (pregunta_id, texto, es_correcta, orden) VALUES ($1, $2, $3, $4)',
              [preguntaId, opcion.texto, opcion.esCorrecta, orden + 1],
            );
          }
        }
        return true;
      });
    },

    async agregarRecurso(uid, actividadId, datos) {
      const aula = await aulaDeActividad(pool, uid, actividadId);
      if (!aula) throw errores.prohibido('Solo el docente del aula puede adjuntar archivos a sus actividades');
      const resultado = await pool.query<{ id: string }>(
        `INSERT INTO actividad_recurso (actividad_id, objeto_key, nombre, mime, tamano, subido_por)
         SELECT $1, $2, $3, $4, $5, u.id
         FROM usuario u WHERE u.uid_firebase = $6
         RETURNING id`,
        [
          actividadId,
          datos.objetoKey,
          datos.nombre,
          datos.mime ?? null,
          datos.tamano ?? null,
          uid,
        ],
      );
      const id = resultado.rows[0]?.id;
      if (!id) throw errores.datosInvalidos('No se encontró el usuario que sube el archivo');
      return { id };
    },

    async eliminarRecurso(uid, recursoId) {
      const acceso = await pool.query<{ id: string }>(
        `SELECT r.id FROM actividad_recurso r
         JOIN actividad act ON act.id = r.actividad_id
         JOIN unidad un ON un.id = act.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         JOIN usuario u ON u.id = g.docente_id
         WHERE r.id = $1 AND u.uid_firebase = $2`,
        [recursoId, uid],
      );
      if (!acceso.rows[0]) {
        throw errores.prohibido('Solo el docente del aula puede eliminar archivos de sus actividades');
      }
      const resultado = await pool.query('DELETE FROM actividad_recurso WHERE id = $1', [recursoId]);
      return (resultado.rowCount ?? 0) > 0;
    },
  };
}

const esFechaHora = z.string().datetime({ offset: true });

const esquemaAula = z.object({ nombre: z.string().trim().min(3).max(160).optional(), descripcion: z.string().trim().max(2000).optional() }).strict();

const esquemaUnidad = z
  .object({ titulo: z.string().trim().min(3).max(160), numero: z.number().int().min(1).max(20).optional() })
  .strict();
const esquemaUnidadParcial = esquemaUnidad.partial().strict();

const esquemaContenido = z
  .object({
    tipo: z.enum([
      'PDF',
      'VIDEO',
      'ENLACE',
      'ANUNCIO',
      'IMAGEN',
      'DOCUMENTO',
      'PRESENTACION',
      'HOJA_CALCULO',
      'ARCHIVO',
    ]),
    titulo: z.string().trim().min(3).max(160),
    descripcion: z.string().trim().max(2000).optional(),
    objetoKey: z.string().trim().min(3).max(300).optional(),
    urlExterna: z.string().url().max(500).optional(),
    mime: z.string().trim().max(120).optional(),
    tamano: z.number().int().positive().optional(),
  })
  .strict();
const esquemaContenidoParcial = z
  .object({
    tipo: z
      .enum([
        'PDF',
        'VIDEO',
        'ENLACE',
        'ANUNCIO',
        'IMAGEN',
        'DOCUMENTO',
        'PRESENTACION',
        'HOJA_CALCULO',
        'ARCHIVO',
      ])
      .optional(),
    titulo: z.string().trim().min(3).max(160).optional(),
    descripcion: z.string().trim().max(2000).optional(),
    objetoKey: z.string().trim().min(3).max(300).optional(),
    urlExterna: z.string().url().max(500).optional(),
    mime: z.string().trim().max(120).optional(),
    tamano: z.number().int().positive().optional(),
  })
  .strict();

const esquemaActividad = z
  .object({
    tipo: z.enum(['TAREA', 'CUESTIONARIO', 'FORO']),
    titulo: z.string().trim().min(3).max(160),
    instrucciones: z.string().trim().max(4000).optional(),
    cierraEn: esFechaHora.optional(),
    corte: z.number().int().min(1).max(3),
    peso: z.number().min(1).max(100),
    notaMaxima: z.number().min(1).max(5).optional(),
    formatosPermitidos: z
      .array(z.string().trim().regex(/^[a-z0-9]{2,8}$/))
      .max(10)
      .optional(),
    revisionPermitida: z.boolean().optional(),
  })
  .strict();
const esquemaActividadParcial = z
  .object({
    titulo: z.string().trim().min(3).max(160).optional(),
    instrucciones: z.string().trim().max(4000).optional(),
    cierraEn: esFechaHora.optional(),
    peso: z.number().min(1).max(100).optional(),
    notaMaxima: z.number().min(1).max(5).optional(),
    formatosPermitidos: z
      .array(z.string().trim().regex(/^[a-z0-9]{2,8}$/))
      .max(10)
      .optional(),
    revisionPermitida: z.boolean().optional(),
  })
  .strict();

const esquemaOpcionCuestionario = z
  .object({
    texto: z.string().trim().min(1).max(500),
    esCorrecta: z.boolean(),
  })
  .strict();
const esquemaPreguntaCuestionario = z
  .object({
    enunciado: z.string().trim().min(3).max(2000),
    tipo: z.enum(['UNICA', 'MULTIPLE']).optional(),
    opciones: z.array(esquemaOpcionCuestionario).min(2).max(10),
  })
  .strict();
const esquemaCuestionario = z
  .object({
    revisionPermitida: z.boolean().default(false),
    preguntas: z.array(esquemaPreguntaCuestionario).min(1).max(50),
  })
  .strict();

const esquemaRecurso = z
  .object({
    objetoKey: z.string().trim().min(3).max(300),
    nombre: z.string().trim().min(1).max(200),
    mime: z.string().trim().max(120).optional(),
    tamano: z.number().int().positive().optional(),
  })
  .strict();

const idParam = z.object({ id: z.string().uuid() });

/** Rutas de edición del aula para el docente dueño del grupo. */
export function registrarRutasAulasDocente(
  app: FastifyInstance,
  repo: RepositorioAulasDocente,
): void {
  const docente = [app.autenticar, app.requerirRoles('DOCENTE', 'ADMIN_ACADEMICO')];
  const soloAdminAcademico = [app.autenticar, app.requerirRoles('ADMIN_ACADEMICO')];

  // El nombre/descripción del aula los administra la oficina académica; el docente no los edita.
  app.put('/api/v1/aulas/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaAula.parse(peticion.body ?? {});
    await repo.actualizarAula(peticion.actor!.uid, id, datos, true);
    return { ok: true };
  });

  app.post('/api/v1/aulas/:id/unidades', { preHandler: docente }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaUnidad.parse(peticion.body ?? {});
    return respuesta.code(201).send(await repo.crearUnidad(peticion.actor!.uid, id, datos));
  });

  app.put('/api/v1/unidades/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaUnidadParcial.parse(peticion.body ?? {});
    await repo.actualizarUnidad(peticion.actor!.uid, id, datos);
    return { ok: true };
  });

  app.delete('/api/v1/unidades/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    await repo.eliminarUnidad(peticion.actor!.uid, id);
    return { eliminado: id };
  });

  app.post('/api/v1/unidades/:id/contenidos', { preHandler: docente }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaContenido.parse(peticion.body ?? {});
    return respuesta.code(201).send(await repo.crearContenido(peticion.actor!.uid, id, datos));
  });

  app.put('/api/v1/contenidos/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaContenidoParcial.parse(peticion.body ?? {});
    await repo.actualizarContenido(peticion.actor!.uid, id, datos);
    return { ok: true };
  });

  app.delete('/api/v1/contenidos/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    await repo.eliminarContenido(peticion.actor!.uid, id);
    return { eliminado: id };
  });

  app.post('/api/v1/unidades/:id/actividades', { preHandler: docente }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const { cierraEn, ...datos } = esquemaActividad.parse(peticion.body ?? {});
    const actividad = await repo.crearActividad(peticion.actor!.uid, id, {
      ...datos,
      ...(cierraEn ? { cierraEn: new Date(cierraEn) } : {}),
    });
    return respuesta.code(201).send(actividad);
  });

  app.put('/api/v1/actividades/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const { cierraEn, ...datos } = esquemaActividadParcial.parse(peticion.body ?? {});
    await repo.actualizarActividad(peticion.actor!.uid, id, {
      ...datos,
      ...(cierraEn ? { cierraEn: new Date(cierraEn) } : {}),
    });
    return { ok: true };
  });

  app.delete('/api/v1/actividades/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    await repo.eliminarActividad(peticion.actor!.uid, id);
    return { eliminado: id };
  });

  // Editor completo de la actividad (sin ventanas emergentes): datos y preguntas con respuestas.
  app.get('/api/v1/actividades/:id/editor', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    return repo.detalleEditor(peticion.actor!.uid, id);
  });

  app.put('/api/v1/actividades/:id/cuestionario', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaCuestionario.parse(peticion.body ?? {});
    await repo.reemplazarCuestionario(peticion.actor!.uid, id, datos);
    return { ok: true };
  });

  // Archivos/materiales propios de una actividad (tareas, exámenes o foros).
  app.post('/api/v1/actividades/:id/recursos', { preHandler: docente }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaRecurso.parse(peticion.body ?? {});
    return respuesta.code(201).send(await repo.agregarRecurso(peticion.actor!.uid, id, datos));
  });

  app.delete('/api/v1/recursos/:id', { preHandler: docente }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    await repo.eliminarRecurso(peticion.actor!.uid, id);
    return { eliminado: id };
  });
}
