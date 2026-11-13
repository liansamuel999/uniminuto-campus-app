import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface ListaRevocaciones {
  version: number;
  actualizadoEn: string | null;
  carnets: string[];
}

export interface EventoAcceso {
  id: string;
  timestamp: string;
  carnetId: string;
  resultado: string;
}

export interface RepositorioAcceso {
  listarRevocaciones(): Promise<ListaRevocaciones>;
  registrarAccesos(uidFirebase: string, eventos: EventoAcceso[]): Promise<number>;
}

export const esquemaLote = z
  .object({
    eventos: z
      .array(
        z.object({
          id: z.string().uuid(),
          timestamp: z.string().datetime({ offset: true }),
          carnetId: z.string().uuid(),
          resultado: z.string().trim().min(1).max(80),
        }),
      )
      .min(1, 'El lote no puede estar vacío')
      .max(100, 'El lote admite como máximo 100 eventos'),
  })
  .strict();

export function crearRepositorioAcceso(pool: Pool): RepositorioAcceso {
  return {
    async listarRevocaciones() {
      const resultado = await pool.query<{ carnet_id: string; desde: string | Date }>(
        'SELECT carnet_id, desde FROM lista_revocacion ORDER BY desde DESC',
      );
      const desde = resultado.rows.map((fila) => (fila.desde instanceof Date ? fila.desde : new Date(fila.desde)));
      const version = desde.reduce((maximo, fecha) => Math.max(maximo, fecha.getTime()), 0);
      return {
        version,
        actualizadoEn: desde.length > 0 ? desde[0]!.toISOString() : null,
        carnets: resultado.rows.map((fila) => fila.carnet_id),
      };
    },

    async registrarAccesos(uidFirebase, eventos) {
      const actor = await pool.query<{ id: string }>('SELECT id FROM usuario WHERE uid_firebase = $1', [
        uidFirebase,
      ]);
      const actorId = actor.rows[0]?.id ?? null;

      let insertados = 0;
      for (const evento of eventos) {
        const resultado = await pool.query<{ id: string }>(
          `INSERT INTO evento_auditoria (id, timestamp, actor_id, accion, recurso, resultado)
           VALUES ($1, $2, $3, 'VALIDAR_ACCESO', $4, $5)
           ON CONFLICT (id) DO NOTHING
           RETURNING id`,
          [evento.id, evento.timestamp, actorId, `carnet:${evento.carnetId}`, evento.resultado],
        );
        insertados += resultado.rowCount ?? 0;
      }
      return insertados;
    },
  };
}

/** Rutas de acceso offline y auditoría del validador (§6.1, §8.1). */
export function registrarRutasAcceso(app: FastifyInstance, repositorio: RepositorioAcceso): void {
  app.get(
    '/api/v1/acceso/revocaciones',
    { preHandler: [app.autenticar, app.requerirRoles('SEGURIDAD')] },
    async () => repositorio.listarRevocaciones(),
  );

  app.post(
    '/api/v1/auditoria/accesos',
    { preHandler: [app.autenticar, app.requerirRoles('SEGURIDAD')] },
    async (peticion, respuesta) => {
      const lote = esquemaLote.parse(peticion.body ?? {});
      if (!peticion.actor) throw errores.noAutorizado();
      const insertados = await repositorio.registrarAccesos(peticion.actor.uid, lote.eventos);
      return respuesta.code(201).send({ recibidos: lote.eventos.length, insertados });
    },
  );
}
