import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import type { Env } from '../../config/env.js';
import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';
import { calcularEstadoEntrega, type EstadoEntrega } from '../../lib/entregas.js';

export interface EntregaCreada {
  id: string;
  estado: EstadoEntrega;
  recibidaEn: string;
}

export interface EntregaListada {
  id: string;
  estudiante: string;
  texto: string | null;
  creadaEnCliente: string;
  recibidaEnServidor: string;
  estado: string;
}

export interface RepositorioEntregas {
  crear(
    uidFirebase: string,
    datos: {
      entregaId: string;
      actividadId: string;
      texto?: string;
      adjuntos: unknown[];
      creadaEnCliente: Date;
    },
  ): Promise<EntregaCreada>;
  listarPorActividad(uidFirebase: string, actividadId: string): Promise<EntregaListada[]>;
}

const esquemaEntrega = z
  .object({
    entregaId: z.string().uuid(),
    actividadId: z.string().uuid(),
    texto: z.string().max(10_000).optional(),
    adjuntos: z.array(z.record(z.string(), z.unknown())).max(10).default([]),
    creadaEnCliente: z.string().datetime({ offset: true }),
  })
  .strict();

export function crearRepositorioEntregas(pool: Pool, env: Env): RepositorioEntregas {
  return {
    async crear(uidFirebase, datos) {
      return withTx(pool, async (cliente) => {
        const contexto = await cliente.query<{
          actividad_id: string;
          cierra_en: string | Date | null;
          inscripcion_id: string;
        }>(
          `SELECT a.id AS actividad_id, a.cierra_en, i.id AS inscripcion_id
           FROM actividad a
           JOIN unidad un ON un.id = a.unidad_id
           JOIN aula au ON au.id = un.aula_id
           JOIN grupo g ON g.id = au.grupo_id
           JOIN inscripcion i ON i.grupo_id = g.id
           JOIN usuario u ON u.id = i.estudiante_id
           WHERE a.id = $1 AND u.uid_firebase = $2`,
          [datos.actividadId, uidFirebase],
        );
        const fila = contexto.rows[0];
        if (!fila) throw errores.noEncontrado('La actividad no existe o no estás inscrito en su grupo');

        const ahora = new Date();
        const cierra = fila.cierra_en
          ? fila.cierra_en instanceof Date
            ? fila.cierra_en
            : new Date(fila.cierra_en)
          : new Date(ahora.getTime() + 365 * 86_400_000);

        const evaluacion = calcularEstadoEntrega({
          creadaEnCliente: datos.creadaEnCliente,
          cierraEn: cierra,
          recibidaEnServidor: ahora,
          graciaHoras: env.ENTREGA_GRACIA_HORAS,
        });
        if (!evaluacion.aceptada) {
          throw errores.conflicto('La entrega llegó después del plazo con gracia');
        }

        const insertada = await cliente.query<{ id: string; recibida_en_servidor: string | Date }>(
          `INSERT INTO entrega (id, actividad_id, estudiante_id, texto, adjuntos, creada_en_cliente, estado)
           SELECT $1, $2, i.estudiante_id, $3, $4::jsonb, $5, $6
           FROM inscripcion i WHERE i.id = $7
           ON CONFLICT (id) DO NOTHING
           RETURNING id, recibida_en_servidor`,
          [
            datos.entregaId,
            datos.actividadId,
            datos.texto ?? null,
            JSON.stringify(datos.adjuntos),
            datos.creadaEnCliente.toISOString(),
            evaluacion.estado,
            fila.inscripcion_id,
          ],
        );

        if (!insertada.rows[0]) {
          // Idempotencia: mismo entregaId devuelve la respuesta original sin duplicar.
          const existente = await cliente.query<{ id: string; estado: string; recibida_en_servidor: string | Date }>(
            'SELECT id, estado, recibida_en_servidor FROM entrega WHERE id = $1',
            [datos.entregaId],
          );
          const original = existente.rows[0];
          if (!original) throw errores.conflicto('No se pudo registrar la entrega');
          return {
            id: original.id,
            estado: original.estado as EstadoEntrega,
            recibidaEn: (original.recibida_en_servidor instanceof Date
              ? original.recibida_en_servidor
              : new Date(original.recibida_en_servidor)
            ).toISOString(),
          };
        }

        const recibida = insertada.rows[0].recibida_en_servidor;
        return {
          id: insertada.rows[0].id,
          estado: evaluacion.estado,
          recibidaEn: (recibida instanceof Date ? recibida : new Date(recibida)).toISOString(),
        };
      });
    },

    async listarPorActividad(uidFirebase, actividadId) {
      const acceso = await pool.query<{ id: string }>(
        `SELECT a.id FROM actividad a
         JOIN unidad un ON un.id = a.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         JOIN usuario u ON u.id = g.docente_id
         WHERE a.id = $1 AND u.uid_firebase = $2`,
        [actividadId, uidFirebase],
      );
      if (!acceso.rows[0]) throw errores.noEncontrado('La actividad no existe o no es de tus grupos');

      const resultado = await pool.query<{
        id: string;
        estudiante: string;
        texto: string | null;
        creada_en_cliente: string | Date;
        recibida_en_servidor: string | Date;
        estado: string;
      }>(
        `SELECT e.id, u.nombres || ' ' || u.apellidos AS estudiante, e.texto,
                e.creada_en_cliente, e.recibida_en_servidor, e.estado
         FROM entrega e JOIN usuario u ON u.id = e.estudiante_id
         WHERE e.actividad_id = $1 ORDER BY e.recibida_en_servidor DESC`,
        [actividadId],
      );

      const iso = (valor: string | Date) => (valor instanceof Date ? valor : new Date(valor)).toISOString();
      return resultado.rows.map((fila) => ({
        id: fila.id,
        estudiante: fila.estudiante,
        texto: fila.texto,
        creadaEnCliente: iso(fila.creada_en_cliente),
        recibidaEnServidor: iso(fila.recibida_en_servidor),
        estado: fila.estado,
      }));
    },
  };
}

export function registrarRutasEntregas(app: FastifyInstance, repo: RepositorioEntregas): void {
  app.post('/api/v1/entregas', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const datos = esquemaEntrega.parse(peticion.body ?? {});
    const entrega = await repo.crear(peticion.actor!.uid, {
      entregaId: datos.entregaId,
      actividadId: datos.actividadId,
      ...(datos.texto !== undefined ? { texto: datos.texto } : {}),
      adjuntos: datos.adjuntos,
      creadaEnCliente: new Date(datos.creadaEnCliente),
    });
    return respuesta.code(201).send(entrega);
  });

  app.get('/api/v1/actividades/:id/entregas', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    return repo.listarPorActividad(peticion.actor!.uid, id);
  });
}
