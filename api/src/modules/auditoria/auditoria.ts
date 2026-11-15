import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

export interface ActorAuditoria {
  id: string;
  nombre: string;
  correo: string;
}

export interface EventoAuditoria {
  id: string;
  timestamp: string;
  accion: string;
  recurso: string;
  resultado: string;
  actor: ActorAuditoria | null;
}

export interface FiltrosAuditoria {
  desde?: Date;
  hasta?: Date;
  accion?: string;
  actorId?: string;
  antesDe?: Date;
  limite: number;
}

export interface RepositorioAuditoria {
  listar(filtros: FiltrosAuditoria): Promise<EventoAuditoria[]>;
  acciones(): Promise<string[]>;
}

/** Bitácora de solo lectura (§8.1). Nunca expone actualización ni borrado. */
export function crearRepositorioAuditoria(pool: Pool): RepositorioAuditoria {
  return {
    async listar(filtros) {
      const condiciones: string[] = [];
      const valores: unknown[] = [];

      if (filtros.desde) {
        valores.push(filtros.desde);
        condiciones.push(`e.timestamp >= $${valores.length}`);
      }
      if (filtros.hasta) {
        valores.push(filtros.hasta);
        condiciones.push(`e.timestamp <= $${valores.length}`);
      }
      if (filtros.accion) {
        valores.push(filtros.accion);
        condiciones.push(`e.accion = $${valores.length}`);
      }
      if (filtros.actorId) {
        valores.push(filtros.actorId);
        condiciones.push(`e.actor_id = $${valores.length}`);
      }
      if (filtros.antesDe) {
        valores.push(filtros.antesDe);
        condiciones.push(`e.timestamp < $${valores.length}`);
      }
      valores.push(filtros.limite);

      const resultado = await pool.query<{
        id: string;
        timestamp: string | Date;
        accion: string;
        recurso: string;
        resultado: string;
        actor_id: string | null;
        actor_nombre: string | null;
        actor_correo: string | null;
      }>(
        `SELECT e.id, e.timestamp, e.accion, e.recurso, e.resultado,
                u.id AS actor_id,
                u.nombres || ' ' || u.apellidos AS actor_nombre,
                u.correo AS actor_correo
         FROM evento_auditoria e
         LEFT JOIN usuario u ON u.id = e.actor_id
         ${condiciones.length > 0 ? `WHERE ${condiciones.join(' AND ')}` : ''}
         ORDER BY e.timestamp DESC, e.id DESC
         LIMIT $${valores.length}`,
        valores,
      );

      return resultado.rows.map((fila) => ({
        id: fila.id,
        timestamp: (fila.timestamp instanceof Date
          ? fila.timestamp
          : new Date(fila.timestamp)
        ).toISOString(),
        accion: fila.accion,
        recurso: fila.recurso,
        resultado: fila.resultado,
        actor:
          fila.actor_id && fila.actor_nombre && fila.actor_correo
            ? { id: fila.actor_id, nombre: fila.actor_nombre, correo: fila.actor_correo }
            : null,
      }));
    },

    async acciones() {
      const resultado = await pool.query<{ accion: string }>(
        'SELECT DISTINCT accion FROM evento_auditoria ORDER BY accion',
      );
      return resultado.rows.map((fila) => fila.accion);
    },
  };
}

const esquemaFiltros = z
  .object({
    desde: z.string().datetime({ offset: true }).optional(),
    hasta: z.string().datetime({ offset: true }).optional(),
    accion: z.string().trim().min(2).max(80).optional(),
    actorId: z.string().uuid().optional(),
    antesDe: z.string().datetime({ offset: true }).optional(),
    limite: z.coerce.number().int().min(1).max(200).default(50),
  })
  .strict();

/** Rutas de auditoría: solo el rol Auditor, solo lectura (§7.7, §8.1). */
export function registrarRutasAuditoria(
  app: FastifyInstance,
  repo: RepositorioAuditoria,
): void {
  app.get(
    '/api/v1/auditoria',
    { preHandler: [app.autenticar, app.requerirRoles('AUDITOR')] },
    async (peticion) => {
      const filtros = esquemaFiltros.parse(peticion.query ?? {});
      return repo.listar({
        ...(filtros.desde ? { desde: new Date(filtros.desde) } : {}),
        ...(filtros.hasta ? { hasta: new Date(filtros.hasta) } : {}),
        ...(filtros.accion ? { accion: filtros.accion } : {}),
        ...(filtros.actorId ? { actorId: filtros.actorId } : {}),
        ...(filtros.antesDe ? { antesDe: new Date(filtros.antesDe) } : {}),
        limite: filtros.limite,
      });
    },
  );

  app.get(
    '/api/v1/auditoria/acciones',
    { preHandler: [app.autenticar, app.requerirRoles('AUDITOR')] },
    async () => repo.acciones(),
  );
}
