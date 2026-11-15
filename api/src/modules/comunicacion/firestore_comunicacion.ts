import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface AnuncioLeido {
  id: string;
  titulo: string;
  cuerpo: string;
  importante: boolean;
  autorNombre: string;
  creadoEn: string | null;
}

export interface HiloLeido {
  id: string;
  titulo: string;
  autorUid: string;
  autorNombre: string;
  creadoEn: string | null;
}

export interface MensajeLeido {
  id: string;
  texto: string;
  autorUid: string;
  autorNombre: string;
  creadoEn: string | null;
}

export interface RepositorioComunicacion {
  anuncios(uid: string, aulaId: string, esAdmin: boolean): Promise<AnuncioLeido[] | null>;
  publicarAnuncio(
    uid: string,
    aulaId: string,
    datos: { titulo: string; cuerpo: string; importante: boolean; autorNombre: string },
  ): Promise<{ id: string } | null>;
  hilos(uid: string, foroId: string, esAdmin: boolean): Promise<HiloLeido[] | null>;
  crearHilo(
    uid: string,
    foroId: string,
    datos: { titulo: string; autorNombre: string },
  ): Promise<{ id: string } | null>;
  mensajes(uid: string, foroId: string, hiloId: string): Promise<MensajeLeido[] | null>;
  enviarMensaje(
    uid: string,
    foroId: string,
    hiloId: string,
    datos: { texto: string; autorNombre: string },
  ): Promise<{ id: string }>;
}

const iso = (valor: unknown): string | null => {
  if (valor == null) return null;
  if (typeof valor === 'string') return valor;
  const conFecha = valor as { toDate?: () => Date };
  if (typeof conFecha.toDate === 'function') return conFecha.toDate().toISOString();
  return null;
};

/**
 * Foros y anuncios en Firestore, servidos por la API con el Admin SDK (D-78).
 *
 * Las reglas de Firestore autorizan lecturas por documento, pero no son válidas para las
 * consultas de lista que necesita la app (el motor evalúa reglas con `get()` de forma distinta
 * para queries). La API valida la pertenencia al aula en SQL y lee/escribe con privilegios.
 */
export function crearRepositorioComunicacion(pool: Pool): RepositorioComunicacion {
  async function base() {
    const { getApps } = await import('firebase-admin/app');
    const app = getApps()[0];
    if (!app) {
      throw errores.noDisponible('Firestore no está configurado en este entorno');
    }
    const { getFirestore } = await import('firebase-admin/firestore');
    return getFirestore(app);
  }

  async function accesoAula(uid: string, aulaId: string) {
    const resultado = await pool.query<{ es_docente: boolean; es_estudiante: boolean }>(
      `SELECT (g.docente_id = u.id) AS es_docente,
              EXISTS (SELECT 1 FROM inscripcion i
                      WHERE i.grupo_id = g.id AND i.estudiante_id = u.id AND i.estado = 'ACTIVA') AS es_estudiante
       FROM aula au JOIN grupo g ON g.id = au.grupo_id
       JOIN usuario u ON u.uid_firebase = $2
       WHERE au.id = $1`,
      [aulaId, uid],
    );
    return resultado.rows[0] ?? null;
  }

  async function accesoForo(uid: string, foroId: string) {
    const resultado = await pool.query<{
      aula_id: string;
      titulo: string;
      es_docente: boolean;
      es_estudiante: boolean;
      docente_nombre: string | null;
    }>(
      `SELECT au.id AS aula_id, act.titulo,
              (g.docente_id = u.id) AS es_docente,
              EXISTS (SELECT 1 FROM inscripcion i
                      WHERE i.grupo_id = g.id AND i.estudiante_id = u.id AND i.estado = 'ACTIVA') AS es_estudiante,
              d.nombres || ' ' || d.apellidos AS docente_nombre
       FROM actividad act
       JOIN unidad un ON un.id = act.unidad_id
       JOIN aula au ON au.id = un.aula_id
       JOIN grupo g ON g.id = au.grupo_id
       JOIN usuario u ON u.uid_firebase = $2
       LEFT JOIN usuario d ON d.id = g.docente_id
       WHERE act.id = $1 AND act.tipo = 'FORO'`,
      [foroId, uid],
    );
    return resultado.rows[0] ?? null;
  }

  async function nombreDeUsuario(uid: string): Promise<string> {
    const resultado = await pool.query<{ nombre: string }>(
      `SELECT nombres || ' ' || apellidos AS nombre FROM usuario WHERE uid_firebase = $1`,
      [uid],
    );
    return resultado.rows[0]?.nombre ?? 'Participante';
  }

  return {
    async anuncios(uid, aulaId, esAdmin) {
      const acceso = await accesoAula(uid, aulaId);
      if (!acceso) return null;
      if (!esAdmin && !acceso.es_docente && !acceso.es_estudiante) return null;

      const db = await base();
      const snapshot = await db.collection('anuncios').doc(aulaId).collection('items').get();
      const anuncios = snapshot.docs.map((doc) => {
        const datos = doc.data();
        return {
          id: doc.id,
          titulo: `${datos.titulo ?? 'Anuncio'}`,
          cuerpo: `${datos.cuerpo ?? ''}`,
          importante: datos.importante === true,
          autorNombre: `${datos.autor_nombre ?? 'Docente'}`,
          creadoEn: iso(datos.creado_en),
        };
      });
      return anuncios.sort((a, b) => `${b.creadoEn ?? ''}`.localeCompare(`${a.creadoEn ?? ''}`));
    },

    async publicarAnuncio(uid, aulaId, datos) {
      const acceso = await accesoAula(uid, aulaId);
      if (!acceso) return null;
      if (!acceso.es_docente) {
        throw errores.prohibido('Solo el docente del aula puede publicar anuncios');
      }
      const db = await base();
      const { FieldValue } = await import('firebase-admin/firestore');
      const referencia = await db.collection('anuncios').doc(aulaId).collection('items').add({
        titulo: datos.titulo,
        cuerpo: datos.cuerpo,
        importante: datos.importante,
        autor_uid: uid,
        autor_nombre: datos.autorNombre || (await nombreDeUsuario(uid)),
        creado_en: FieldValue.serverTimestamp(),
      });
      return { id: referencia.id };
    },

    async hilos(uid, foroId, esAdmin) {
      const acceso = await accesoForo(uid, foroId);
      if (!acceso) return null;
      if (!esAdmin && !acceso.es_docente && !acceso.es_estudiante) return null;

      const db = await base();
      const snapshot = await db.collection('foros').doc(foroId).collection('hilos').get();
      const hilos = snapshot.docs.map((doc) => {
        const datos = doc.data();
        return {
          id: doc.id,
          titulo: `${datos.titulo ?? 'Hilo'}`,
          autorUid: `${datos.autor_uid ?? ''}`,
          autorNombre: `${datos.autor_nombre ?? 'Participante'}`,
          creadoEn: iso(datos.creado_en),
        };
      });
      return hilos.sort((a, b) => `${b.creadoEn ?? ''}`.localeCompare(`${a.creadoEn ?? ''}`));
    },

    async crearHilo(uid, foroId, datos) {
      const acceso = await accesoForo(uid, foroId);
      if (!acceso) return null;
      if (!acceso.es_docente && !acceso.es_estudiante) {
        throw errores.prohibido('No perteneces al aula de este foro');
      }
      const db = await base();
      const { FieldValue } = await import('firebase-admin/firestore');
      const referencia = await db.collection('foros').doc(foroId).collection('hilos').add({
        titulo: datos.titulo,
        autor_uid: uid,
        autor_nombre: datos.autorNombre || (await nombreDeUsuario(uid)),
        aula_id: acceso.aula_id,
        foro_id: foroId,
        creado_en: FieldValue.serverTimestamp(),
      });
      return { id: referencia.id };
    },

    async mensajes(uid, foroId, hiloId) {
      const acceso = await accesoForo(uid, foroId);
      if (!acceso) return null;
      if (!acceso.es_docente && !acceso.es_estudiante) return null;

      const db = await base();
      const snapshot = await db
        .collection('foros')
        .doc(foroId)
        .collection('hilos')
        .doc(hiloId)
        .collection('mensajes')
        .get();
      const mensajes = snapshot.docs.map((doc) => {
        const datos = doc.data();
        return {
          id: doc.id,
          texto: `${datos.texto ?? ''}`,
          autorUid: `${datos.autor_uid ?? ''}`,
          autorNombre: `${datos.autor_nombre ?? 'Participante'}`,
          creadoEn: iso(datos.creado_en),
        };
      });
      return mensajes.sort((a, b) => `${a.creadoEn ?? ''}`.localeCompare(`${b.creadoEn ?? ''}`));
    },

    async enviarMensaje(uid, foroId, hiloId, datos) {
      const acceso = await accesoForo(uid, foroId);
      if (!acceso) throw errores.noEncontrado('El foro no existe');
      if (!acceso.es_docente && !acceso.es_estudiante) {
        throw errores.prohibido('No perteneces al aula de este foro');
      }
      const db = await base();
      const { FieldValue } = await import('firebase-admin/firestore');
      const referencia = await db
        .collection('foros')
        .doc(foroId)
        .collection('hilos')
        .doc(hiloId)
        .collection('mensajes')
        .add({
          texto: datos.texto,
          autor_uid: uid,
          autor_nombre: datos.autorNombre || (await nombreDeUsuario(uid)),
          aula_id: acceso.aula_id,
          creado_en: FieldValue.serverTimestamp(),
        });
      return { id: referencia.id };
    },
  };
}

const esquemaAnuncio = z
  .object({
    titulo: z.string().trim().min(3).max(160),
    cuerpo: z.string().trim().min(3).max(4000),
    importante: z.boolean().default(false),
  })
  .strict();

const esquemaHilo = z.object({ titulo: z.string().trim().min(3).max(160) }).strict();
const esquemaMensaje = z.object({ texto: z.string().trim().min(1).max(4000) }).strict();
const idParam = z.object({ id: z.string().uuid() });
const hiloParam = z.object({ id: z.string().uuid(), hiloId: z.string().trim().min(1).max(120) });

/** Rutas de anuncios y foros respaldadas por Firestore a través de la API (D-78). */
export function registrarRutasComunicacion(
  app: FastifyInstance,
  repo: RepositorioComunicacion,
): void {
  app.get('/api/v1/aulas/:id/anuncios', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const esAdmin = peticion.actor?.roles.includes('ADMIN_ACADEMICO') ?? false;
    const anuncios = await repo.anuncios(peticion.actor!.uid, id, esAdmin);
    if (!anuncios) throw errores.noEncontrado('El aula no existe o no tienes acceso a ella');
    return anuncios;
  });

  app.post('/api/v1/aulas/:id/anuncios', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaAnuncio.parse(peticion.body ?? {});
    const anuncio = await repo.publicarAnuncio(peticion.actor!.uid, id, {
      ...datos,
      autorNombre: '',
    });
    if (!anuncio) throw errores.noEncontrado('El aula no existe o no tienes acceso a ella');
    return respuesta.code(201).send(anuncio);
  });

  app.get('/api/v1/foros/:id/hilos', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const esAdmin = peticion.actor?.roles.includes('ADMIN_ACADEMICO') ?? false;
    const hilos = await repo.hilos(peticion.actor!.uid, id, esAdmin);
    if (!hilos) throw errores.noEncontrado('El foro no existe o no tienes acceso a él');
    return hilos;
  });

  app.post('/api/v1/foros/:id/hilos', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaHilo.parse(peticion.body ?? {});
    const hilo = await repo.crearHilo(peticion.actor!.uid, id, { ...datos, autorNombre: '' });
    if (!hilo) throw errores.noEncontrado('El foro no existe o no tienes acceso a él');
    return respuesta.code(201).send(hilo);
  });

  app.get('/api/v1/foros/:id/hilos/:hiloId/mensajes', { preHandler: app.autenticar }, async (peticion) => {
    const { id, hiloId } = hiloParam.parse(peticion.params);
    const mensajes = await repo.mensajes(peticion.actor!.uid, id, hiloId);
    if (!mensajes) throw errores.noEncontrado('El foro no existe o no tienes acceso a él');
    return mensajes;
  });

  app.post(
    '/api/v1/foros/:id/hilos/:hiloId/mensajes',
    { preHandler: app.autenticar },
    async (peticion, respuesta) => {
      const { id, hiloId } = hiloParam.parse(peticion.params);
      const datos = esquemaMensaje.parse(peticion.body ?? {});
      const mensaje = await repo.enviarMensaje(peticion.actor!.uid, id, hiloId, {
        ...datos,
        autorNombre: '',
      });
      return respuesta.code(201).send(mensaje);
    },
  );
}
