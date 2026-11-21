import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';

export interface EspacioReservable {
  id: string;
  nombre: string;
  tipo: 'INDIVIDUAL' | 'GRUPO';
  capacidad: number;
}

export interface Reservacion {
  id: string;
  espacioId: string;
  espacioNombre: string;
  capacidad: number;
  usuarioId: string;
  usuarioNombre: string;
  inicio: string;
  fin: string;
  estado: string;
}

export interface RepositorioReservaciones {
  listarEspacios(): Promise<EspacioReservable[]>;
  listarDelDia(fecha: string): Promise<Reservacion[]>;
  listarSemana(desde: string): Promise<Reservacion[]>;
  crear(uidFirebase: string, espacioId: string, inicio: Date, fin: Date): Promise<Reservacion>;
  cancelar(uidFirebase: string, reservacionId: string, puedeCancelarAjeno: boolean): Promise<void>;
  mias(uidFirebase: string): Promise<Reservacion[]>;
  todas(): Promise<Reservacion[]>;
}

export const HORARIO = {
  apertura: 6,
  cierre: 20,
  duracionMinima: 10,
  duracionMaxima: 120,
  pasoMinutos: 10,
};
const OFFSET_BOGOTA_MS = -5 * 60 * 60 * 1000;

const CONSULTA = `
  SELECT r.id, r.espacio_id AS "espacioId", e.nombre AS "espacioNombre", e.capacidad,
         r.usuario_id AS "usuarioId", u.nombres || ' ' || u.apellidos AS "usuarioNombre",
         r.inicio, r.fin, r.estado
  FROM reservacion r
  JOIN espacio_reservable e ON e.id = r.espacio_id
  JOIN usuario u ON u.id = r.usuario_id
`;

interface FilaReservacion {
  id: string;
  espacioId: string;
  espacioNombre: string;
  capacidad: number;
  usuarioId: string;
  usuarioNombre: string;
  inicio: string | Date;
  fin: string | Date;
  estado: string;
}

function aReservacion(fila: FilaReservacion): Reservacion {
  const aIso = (valor: string | Date) =>
    (valor instanceof Date ? valor : new Date(valor)).toISOString();
  return {
    id: fila.id,
    espacioId: fila.espacioId,
    espacioNombre: fila.espacioNombre,
    capacidad: fila.capacidad,
    usuarioId: fila.usuarioId,
    usuarioNombre: fila.usuarioNombre,
    inicio: aIso(fila.inicio),
    fin: aIso(fila.fin),
    estado: fila.estado,
  };
}

/** Valida el horario de la reserva en hora de Colombia (UTC-5, sin horario de verano). */
export function validarFranja(inicio: Date, fin: Date, ahora: Date = new Date()): void {
  if (!(fin > inicio)) throw errores.datosInvalidos('La hora de fin debe ser posterior al inicio');
  const minutos = (fin.getTime() - inicio.getTime()) / 60_000;
  const paso = HORARIO.pasoMinutos;
  const minutosInicio = new Date(inicio.getTime() + OFFSET_BOGOTA_MS);
  const minutosFin = new Date(fin.getTime() + OFFSET_BOGOTA_MS);
  if (minutosInicio.getUTCMinutes() % paso !== 0 || minutosFin.getUTCMinutes() % paso !== 0) {
    throw errores.datosInvalidos(`Las reservas se hacen en bloques de ${paso} minutos`);
  }
  if (minutos < HORARIO.duracionMinima) {
    throw errores.datosInvalidos(`La reserva debe durar al menos ${HORARIO.duracionMinima} minutos`);
  }
  if (minutos > HORARIO.duracionMaxima) {
    throw errores.datosInvalidos(`La reserva no puede durar más de ${HORARIO.duracionMaxima} minutos`);
  }
  if (inicio.getTime() < ahora.getTime() - 5 * 60_000) {
    throw errores.datosInvalidos('No se puede reservar en el pasado');
  }
  const horaInicio = new Date(inicio.getTime() + OFFSET_BOGOTA_MS).getUTCHours();
  const finBogota = new Date(fin.getTime() + OFFSET_BOGOTA_MS);
  const horaFin = finBogota.getUTCHours() + finBogota.getUTCMinutes() / 60;
  if (horaInicio < HORARIO.apertura || horaFin > HORARIO.cierre) {
    const apertura = String(HORARIO.apertura).padStart(2, '0');
    const cierre = String(HORARIO.cierre).padStart(2, '0');
    throw errores.datosInvalidos(
      `El horario de reservas es de ${apertura}:00 a ${cierre}:00 (hora Colombia)`,
    );
  }
}

export function crearRepositorioReservaciones(pool: Pool): RepositorioReservaciones {
  return {
    async listarEspacios() {
      const resultado = await pool.query<EspacioReservable>(
        'SELECT id, nombre, tipo, capacidad FROM espacio_reservable WHERE activo ORDER BY tipo DESC, capacidad, nombre',
      );
      return resultado.rows;
    },

    async listarDelDia(fecha) {
      const resultado = await pool.query<FilaReservacion>(
        `${CONSULTA}
         WHERE r.estado = 'CONFIRMADA'
           AND r.fin >= now()
           AND r.inicio >= $1::date AND r.inicio < ($1::date + interval '1 day')
         ORDER BY r.inicio`,
        [fecha],
      );
      return resultado.rows.map(aReservacion);
    },

    async listarSemana(desde) {
      const resultado = await pool.query<FilaReservacion>(
        `${CONSULTA}
         WHERE r.estado = 'CONFIRMADA'
           AND r.fin >= now()
           AND r.inicio >= $1::date AND r.inicio < ($1::date + interval '7 days')
         ORDER BY r.inicio`,
        [desde],
      );
      return resultado.rows.map(aReservacion);
    },

    async crear(uidFirebase, espacioId, inicio, fin) {
      return withTx(pool, async (cliente) => {
        const usuario = await cliente.query<{ id: string }>(
          'SELECT id FROM usuario WHERE uid_firebase = $1',
          [uidFirebase],
        );
        const usuarioId = usuario.rows[0]?.id;
        if (!usuarioId) throw errores.noEncontrado('El usuario autenticado no está registrado');

        const espacio = await cliente.query<EspacioReservable>(
          'SELECT id, nombre, tipo, capacidad FROM espacio_reservable WHERE id = $1 AND activo',
          [espacioId],
        );
        if (!espacio.rows[0]) throw errores.noEncontrado('El espacio no existe o está inactivo');

        // SERIALIZABLE + NOT EXISTS: dos reservas concurrentes no pueden solaparse.
        const insertada = await cliente.query<{ id: string }>(
          `INSERT INTO reservacion (espacio_id, usuario_id, inicio, fin)
           SELECT $1, $2, $3, $4
           WHERE NOT EXISTS (
             SELECT 1 FROM reservacion
             WHERE espacio_id = $1 AND estado = 'CONFIRMADA'
               AND inicio < $4 AND fin > $3
           )
           RETURNING id`,
          [espacioId, usuarioId, inicio.toISOString(), fin.toISOString()],
        );
        const id = insertada.rows[0]?.id;
        if (!id) throw errores.conflicto('Ese espacio ya está reservado en ese horario');

        const fila = await cliente.query<FilaReservacion>(`${CONSULTA} WHERE r.id = $1`, [id]);
        return aReservacion(fila.rows[0]!);
      });
    },

    async cancelar(uidFirebase, reservacionId, puedeCancelarAjeno) {
      await withTx(pool, async (cliente) => {
        const fila = await cliente.query<{ usuario_id: string; actor_id: string }>(
          `SELECT r.usuario_id, u.id AS actor_id
           FROM reservacion r JOIN usuario u ON u.uid_firebase = $1
           WHERE r.id = $2 AND r.estado = 'CONFIRMADA'`,
          [uidFirebase, reservacionId],
        );
        const registrada = fila.rows[0];
        if (!registrada) throw errores.noEncontrado('No existe una reserva activa con ese id');
        if (registrada.usuario_id !== registrada.actor_id && !puedeCancelarAjeno) {
          throw errores.prohibido('Solo puedes cancelar tus propias reservas');
        }
        await cliente.query("UPDATE reservacion SET estado = 'CANCELADA' WHERE id = $1", [reservacionId]);
      });
    },

    async mias(uidFirebase) {
      const resultado = await pool.query<FilaReservacion>(
        `${CONSULTA}
         WHERE u.uid_firebase = $1 AND r.estado = 'CONFIRMADA' AND r.fin >= now()
         ORDER BY r.inicio DESC LIMIT 100`,
        [uidFirebase],
      );
      return resultado.rows.map(aReservacion);
    },

    async todas() {
      const resultado = await pool.query<FilaReservacion>(
        `${CONSULTA}
         WHERE r.estado = 'CONFIRMADA' AND r.fin >= now()
         ORDER BY r.inicio DESC LIMIT 200`,
      );
      return resultado.rows.map(aReservacion);
    },
  };
}

const esquemaCreacion = z
  .object({
    espacioId: z.string().uuid(),
    inicio: z.string().datetime({ offset: true }),
    fin: z.string().datetime({ offset: true }),
  })
  .strict();

/** Rutas de reservaciones de espacios de autorecreación. */
export function registrarRutasReservaciones(app: FastifyInstance, repo: RepositorioReservaciones): void {
  app.get('/api/v1/reservaciones/espacios', { preHandler: app.autenticar }, async () =>
    repo.listarEspacios(),
  );

  app.get('/api/v1/reservaciones/disponibilidad', { preHandler: app.autenticar }, async (peticion) => {
    const { fecha } = z.object({ fecha: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }).parse(peticion.query);
    const [espacios, reservas] = await Promise.all([repo.listarEspacios(), repo.listarDelDia(fecha)]);
    return { fecha, espacios, reservas };
  });

  app.get('/api/v1/reservaciones/semana', { preHandler: app.autenticar }, async (peticion) => {
    const { desde } = z
      .object({ desde: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) })
      .parse(peticion.query);
    const [espacios, reservas] = await Promise.all([
      repo.listarEspacios(),
      repo.listarSemana(desde),
    ]);
    const fin = new Date(`${desde}T00:00:00.000Z`);
    fin.setUTCDate(fin.getUTCDate() + 6);
    return { desde, hasta: fin.toISOString().slice(0, 10), espacios, reservas };
  });

  app.get('/api/v1/reservaciones/mias', { preHandler: app.autenticar }, async (peticion) =>
    repo.mias(peticion.actor!.uid),
  );

  app.post('/api/v1/reservaciones', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const datos = esquemaCreacion.parse(peticion.body ?? {});
    const inicio = new Date(datos.inicio);
    const fin = new Date(datos.fin);
    validarFranja(inicio, fin);
    const reserva = await repo.crear(peticion.actor!.uid, datos.espacioId, inicio, fin);
    return respuesta.code(201).send(reserva);
  });

  app.delete('/api/v1/reservaciones/:id', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    const puedeCancelarAjeno = peticion.actor?.roles.includes('ADMIN_ESPACIOS') ?? false;
    await repo.cancelar(peticion.actor!.uid, id, puedeCancelarAjeno);
    return { ok: true, reservacionId: id };
  });

  app.get(
    '/api/v1/reservaciones',
    { preHandler: [app.autenticar, app.requerirRoles('ADMIN_ESPACIOS')] },
    async () => repo.todas(),
  );
}
