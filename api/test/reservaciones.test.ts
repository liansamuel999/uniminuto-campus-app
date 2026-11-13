import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import { AppError } from '../src/lib/errors.js';
import {
  validarFranja,
  type EspacioReservable,
  type RepositorioReservaciones,
  type Reservacion,
} from '../src/modules/reservaciones/reservaciones.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const ESPACIO_ID = '7c1e2b4a-3333-4c2b-9d3e-000000000003';
const RESERVA_ID = '8d1e2b4a-4444-4c2b-9d3e-000000000004';
const UID = 'uid-demo-estudiante';

const espacio: EspacioReservable = {
  id: ESPACIO_ID,
  nombre: 'Sala A (4 personas)',
  tipo: 'GRUPO',
  capacidad: 4,
};

const reserva: Reservacion = {
  id: RESERVA_ID,
  espacioId: ESPACIO_ID,
  espacioNombre: espacio.nombre,
  capacidad: 4,
  usuarioId: 'usuario-1',
  usuarioNombre: 'Juan Pablo Rojas',
  inicio: '2030-01-15T15:00:00.000Z',
  fin: '2030-01-15T16:00:00.000Z',
  estado: 'CONFIRMADA',
};

interface Capturas {
  creacion?: { espacioId: string; inicio: Date; fin: Date };
  cancelacion?: { reservacionId: string; puedeCancelarAjeno: boolean };
}

function repositorioFalso(capturas: Capturas): RepositorioReservaciones {
  return {
    async listarEspacios() {
      return [espacio];
    },
    async listarDelDia() {
      return [reserva];
    },
    async listarSemana() {
      return [reserva];
    },
    async crear(uid, espacioId, inicio, fin) {
      capturas.creacion = { espacioId, inicio, fin };
      return { ...reserva, espacioId, inicio: inicio.toISOString(), fin: fin.toISOString() };
    },
    async cancelar(_uid, reservacionId, puedeCancelarAjeno) {
      capturas.cancelacion = { reservacionId, puedeCancelarAjeno };
      if (!puedeCancelarAjeno && reservacionId === 'otra') {
        throw new AppError('PROHIBIDO', 'no es tuya', 403);
      }
    },
    async mias() {
      return [reserva];
    },
    async todas() {
      return [reserva];
    },
  };
}

async function crearApp(capturas: Capturas = {}) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioReservaciones: repositorioFalso(capturas),
  });
}

async function token(roles: string[] = ['ESTUDIANTE']): Promise<string> {
  return firmarTokenDev({ uid: UID, secreto: SECRETO_PRUEBAS, roles });
}

const FRANJA_VALIDA = {
  espacioId: ESPACIO_ID,
  inicio: '2030-01-15T15:00:00.000Z',
  fin: '2030-01-15T16:00:00.000Z',
};

describe('reglas de la franja horaria', () => {
  it('acepta una reserva de una hora dentro del horario', () => {
    expect(() =>
      validarFranja(new Date('2030-01-15T15:00:00.000Z'), new Date('2030-01-15T16:00:00.000Z')),
    ).not.toThrow();
  });

  it('exige bloques de 10 minutos', () => {
    expect(() =>
      validarFranja(new Date('2030-01-15T15:00:00.000Z'), new Date('2030-01-15T15:05:00.000Z')),
    ).toThrowError(/bloques de 10 minutos/);
  });

  it('rechaza más de 2 horas', () => {
    expect(() =>
      validarFranja(new Date('2030-01-15T15:00:00.000Z'), new Date('2030-01-15T18:00:00.000Z')),
    ).toThrowError(/más de 120 minutos/);
  });

  it('rechaza horarios fuera de 07:00–20:00 en Bogotá', () => {
    // 03:00 UTC = 22:00 en Bogotá.
    expect(() =>
      validarFranja(new Date('2030-01-15T03:00:00.000Z'), new Date('2030-01-15T04:00:00.000Z')),
    ).toThrowError(/06:00 a 20:00/);
  });

  it('rechaza reservas en el pasado', () => {
    expect(() =>
      validarFranja(new Date('2020-01-15T15:00:00.000Z'), new Date('2020-01-15T16:00:00.000Z')),
    ).toThrowError(/pasado/);
  });
});

describe('rutas de reservaciones', () => {
  it('lista los espacios de autorecreación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/reservaciones/espacios',
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    await app.close();
  });

  it('crea una reserva válida', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/reservaciones',
      headers: { authorization: `Bearer ${await token()}` },
      payload: FRANJA_VALIDA,
    });

    expect(respuesta.statusCode).toBe(201);
    expect(capturas.creacion?.espacioId).toBe(ESPACIO_ID);
    await app.close();
  });

  it('rechaza una reserva fuera de horario', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/reservaciones',
      headers: { authorization: `Bearer ${await token()}` },
      payload: { ...FRANJA_VALIDA, inicio: '2030-01-15T03:00:00.000Z', fin: '2030-01-15T04:00:00.000Z' },
    });

    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('lista una semana completa de disponibilidad', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/reservaciones/semana?desde=2030-01-14',
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ desde: '2030-01-14', hasta: '2030-01-20' });
    expect(respuesta.json().reservas).toHaveLength(1);
    await app.close();
  });

  it('el dueño cancela con permiso solo sobre lo propio', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'DELETE',
      url: `/api/v1/reservaciones/${RESERVA_ID}`,
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(capturas.cancelacion).toEqual({ reservacionId: RESERVA_ID, puedeCancelarAjeno: false });
    await app.close();
  });

  it('el admin de espacios puede cancelar reservas ajenas', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'DELETE',
      url: `/api/v1/reservaciones/${RESERVA_ID}`,
      headers: { authorization: `Bearer ${await token(['ADMIN_ESPACIOS'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(capturas.cancelacion?.puedeCancelarAjeno).toBe(true);
    await app.close();
  });

  it('solo el admin de espacios ve todas las reservas', async () => {
    const app = await crearApp();

    const estudiante = await app.inject({
      method: 'GET',
      url: '/api/v1/reservaciones',
      headers: { authorization: `Bearer ${await token()}` },
    });
    expect(estudiante.statusCode).toBe(403);

    const admin = await app.inject({
      method: 'GET',
      url: '/api/v1/reservaciones',
      headers: { authorization: `Bearer ${await token(['ADMIN_ESPACIOS'])}` },
    });
    expect(admin.statusCode).toBe(200);
    await app.close();
  });
});
