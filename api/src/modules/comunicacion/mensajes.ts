import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface Mensaje {
  id: string;
  remitenteId: string;
  remitente: string;
  destinatarioId: string;
  destinatario: string;
  asunto: string;
  cuerpo: string;
  leido: boolean;
  creadoEn: string;
}

export interface ContactoMensaje {
  id: string;
  nombre: string;
  correo: string;
  rol: 'DOCENTE' | 'ESTUDIANTE';
  cursos: string;
}

export interface RepositorioMensajes {
  listar(uidFirebase: string): Promise<{ recibidos: Mensaje[]; enviados: Mensaje[] }>;
  contactos(uidFirebase: string): Promise<ContactoMensaje[]>;
  crear(
    uidFirebase: string,
    datos: { destinatarioId: string; asunto: string; cuerpo: string },
  ): Promise<Mensaje>;
  marcarLeido(uidFirebase: string, id: string): Promise<Mensaje | null>;
}

const CONSULTA = `
  SELECT m.id AS "id",
         r.id AS "remitenteId", r.nombres || ' ' || r.apellidos AS "remitente",
         d.id AS "destinatarioId", d.nombres || ' ' || d.apellidos AS "destinatario",
         m.asunto, m.cuerpo, m.leido, m.creado_en
  FROM mensaje m
  JOIN usuario r ON r.id = m.remitente_id
  JOIN usuario d ON d.id = m.destinatario_id
`;

interface FilaMensaje {
  id: string;
  remitenteId: string;
  remitente: string;
  destinatarioId: string;
  destinatario: string;
  asunto: string;
  cuerpo: string;
  leido: boolean;
  creado_en: string | Date;
}

function aMensaje(fila: FilaMensaje): Mensaje {
  return {
    id: fila.id,
    remitenteId: fila.remitenteId,
    remitente: fila.remitente,
    destinatarioId: fila.destinatarioId,
    destinatario: fila.destinatario,
    asunto: fila.asunto,
    cuerpo: fila.cuerpo,
    leido: fila.leido,
    creadoEn: new Date(fila.creado_en).toISOString(),
  };
}

/** Contactos válidos: docentes y estudiantes que comparten al menos un curso con el usuario. */
const CONSULTA_CONTACTOS = `
  WITH mis_grupos AS (
    SELECT i.grupo_id AS grupo_id
    FROM inscripcion i
    JOIN usuario u ON u.id = i.estudiante_id
    WHERE u.uid_firebase = $1 AND i.estado = 'ACTIVA'
    UNION
    SELECT g.id
    FROM grupo g
    JOIN usuario u ON u.id = g.docente_id
    WHERE u.uid_firebase = $1
  ),
  participantes AS (
    SELECT g.id AS grupo_id, g.docente_id AS usuario_id
    FROM grupo g WHERE g.id IN (SELECT grupo_id FROM mis_grupos)
    UNION
    SELECT i.grupo_id, i.estudiante_id
    FROM inscripcion i
    WHERE i.grupo_id IN (SELECT grupo_id FROM mis_grupos) AND i.estado = 'ACTIVA'
  )
  SELECT u.id, u.nombres || ' ' || u.apellidos AS nombre, u.correo,
         CASE WHEN EXISTS (
           SELECT 1 FROM grupo g2 WHERE g2.id IN (SELECT grupo_id FROM mis_grupos)
             AND g2.docente_id = u.id
         ) THEN 'DOCENTE' ELSE 'ESTUDIANTE' END AS rol,
         COALESCE(string_agg(DISTINCT asg.nombre, ', '), 'Curso compartido') AS cursos
  FROM participantes p
  JOIN usuario u ON u.id = p.usuario_id
  JOIN grupo g ON g.id = p.grupo_id
  JOIN asignatura asg ON asg.id = g.asignatura_id
  JOIN usuario yo ON yo.uid_firebase = $1
  WHERE u.id <> yo.id
  GROUP BY u.id, u.nombres, u.apellidos, u.correo
  ORDER BY rol DESC, u.apellidos, u.nombres
`;

export function crearRepositorioMensajes(pool: Pool): RepositorioMensajes {
  const usuarioId = async (uidFirebase: string): Promise<string> => {
    const fila = await pool.query<{ id: string }>('SELECT id FROM usuario WHERE uid_firebase = $1', [
      uidFirebase,
    ]);
    const id = fila.rows[0]?.id;
    if (!id) throw errores.noEncontrado('El usuario autenticado no está registrado');
    return id;
  };

  return {
    async listar(uidFirebase) {
      const id = await usuarioId(uidFirebase);
      const [recibidos, enviados] = await Promise.all([
        pool.query<FilaMensaje>(
          `${CONSULTA} WHERE m.destinatario_id = $1 ORDER BY m.creado_en DESC LIMIT 200`,
          [id],
        ),
        pool.query<FilaMensaje>(
          `${CONSULTA} WHERE m.remitente_id = $1 ORDER BY m.creado_en DESC LIMIT 100`,
          [id],
        ),
      ]);
      return { recibidos: recibidos.rows.map(aMensaje), enviados: enviados.rows.map(aMensaje) };
    },

    async contactos(uidFirebase) {
      const resultado = await pool.query<ContactoMensaje>(CONSULTA_CONTACTOS, [uidFirebase]);
      return resultado.rows;
    },

    async crear(uidFirebase, datos) {
      const id = await usuarioId(uidFirebase);
      const contactos = await pool.query<ContactoMensaje>(CONSULTA_CONTACTOS, [uidFirebase]);
      if (!contactos.rows.some((contacto) => contacto.id === datos.destinatarioId)) {
        throw errores.datosInvalidos('El destinatario no comparte ningún curso contigo');
      }
      const creado = await pool.query<{ id: string }>(
        `INSERT INTO mensaje (remitente_id, destinatario_id, asunto, cuerpo)
         VALUES ($1, $2, $3, $4) RETURNING id`,
        [id, datos.destinatarioId, datos.asunto, datos.cuerpo],
      );
      const mensaje = await pool.query<FilaMensaje>(`${CONSULTA} WHERE m.id = $1`, [
        creado.rows[0]!.id,
      ]);
      return aMensaje(mensaje.rows[0]!);
    },

    async marcarLeido(uidFirebase, id) {
      const usuario = await usuarioId(uidFirebase);
      const actualizado = await pool.query(
        'UPDATE mensaje SET leido = true WHERE id = $1 AND destinatario_id = $2 RETURNING id',
        [id, usuario],
      );
      if (!actualizado.rows[0]) return null;
      const mensaje = await pool.query<FilaMensaje>(`${CONSULTA} WHERE m.id = $1`, [id]);
      return mensaje.rows[0] ? aMensaje(mensaje.rows[0]) : null;
    },
  };
}

const esquemaMensaje = z
  .object({
    destinatarioId: z.string().uuid(),
    asunto: z.string().trim().min(1).max(160),
    cuerpo: z.string().trim().min(1).max(4000),
  })
  .strict();

const idParam = z.object({ id: z.string().uuid() });

export function registrarRutasMensajes(app: FastifyInstance, repo: RepositorioMensajes): void {
  app.get('/api/v1/mensajes', { preHandler: app.autenticar }, async (peticion) =>
    repo.listar(peticion.actor!.uid),
  );

  app.get('/api/v1/mensajes/contactos', { preHandler: app.autenticar }, async (peticion) =>
    repo.contactos(peticion.actor!.uid),
  );

  app.post('/api/v1/mensajes', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const datos = esquemaMensaje.parse(peticion.body ?? {});
    const mensaje = await repo.crear(peticion.actor!.uid, datos);
    return respuesta.code(201).send(mensaje);
  });

  app.put('/api/v1/mensajes/:id/leido', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const mensaje = await repo.marcarLeido(peticion.actor!.uid, id);
    if (!mensaje) throw errores.noEncontrado('El mensaje no existe o no es tuyo');
    return mensaje;
  });
}
