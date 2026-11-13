import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import { calcularEstadoEntrega } from '../src/lib/entregas.js';
import type { RepositorioEntregas } from '../src/modules/actividades/entregas.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const ACTIVIDAD_ID = '9e1e2b4a-5555-4c2b-9d3e-000000000005';
const ENTREGA_ID = 'ae1e2b4a-6666-4c2b-9d3e-000000000006';

function repoFalso(): RepositorioEntregas {
  return {
    async crear(_uid, datos) {
      return {
        id: datos.entregaId,
        estado: 'ENVIADA',
        recibidaEn: new Date().toISOString(),
      };
    },
    async listarPorActividad() {
      return [
        {
          id: ENTREGA_ID,
          estudiante: 'Juan Pablo Rojas',
          texto: 'Mi taller',
          creadaEnCliente: new Date().toISOString(),
          recibidaEnServidor: new Date().toISOString(),
          estado: 'ENVIADA',
        },
      ];
    },
  };
}

async function app() {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioEntregas: repoFalso(),
  });
}

async function token(roles = ['ESTUDIANTE']) {
  return firmarTokenDev({ uid: 'uid-demo', secreto: SECRETO_PRUEBAS, roles });
}

describe('reglas de entrega (§6.2)', () => {
  const cierra = new Date('2030-01-15T16:00:00.000Z');

  it('es ENVIADA si se preparó antes del cierre aunque llegue después', () => {
    expect(
      calcularEstadoEntrega({
        creadaEnCliente: new Date('2030-01-15T15:30:00.000Z'),
        cierraEn: cierra,
        recibidaEnServidor: new Date('2030-01-15T17:00:00.000Z'),
        graciaHoras: 24,
      }),
    ).toEqual({ aceptada: true, estado: 'ENVIADA' });
  });

  it('es TARDIA si se preparó después del cierre dentro de la gracia', () => {
    expect(
      calcularEstadoEntrega({
        creadaEnCliente: new Date('2030-01-15T17:30:00.000Z'),
        cierraEn: cierra,
        recibidaEnServidor: new Date('2030-01-15T18:00:00.000Z'),
        graciaHoras: 24,
      }),
    ).toEqual({ aceptada: true, estado: 'TARDIA' });
  });

  it('rechaza cuando llega después de la gracia de 24 h', () => {
    expect(
      calcularEstadoEntrega({
        creadaEnCliente: new Date('2030-01-15T17:30:00.000Z'),
        cierraEn: cierra,
        recibidaEnServidor: new Date('2030-01-17T17:00:00.000Z'),
        graciaHoras: 24,
      }),
    ).toEqual({ aceptada: false, motivo: 'FUERA_DE_PLAZO' });
  });
});

describe('rutas de entregas', () => {
  it('registra una entrega', async () => {
    const servidor = await app();
    const respuesta = await servidor.inject({
      method: 'POST',
      url: '/api/v1/entregas',
      headers: { authorization: `Bearer ${await token()}` },
      payload: {
        entregaId: ENTREGA_ID,
        actividadId: ACTIVIDAD_ID,
        texto: 'Mi taller',
        creadaEnCliente: new Date().toISOString(),
      },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json()).toMatchObject({ estado: 'ENVIADA' });
    await servidor.close();
  });

  it('el docente lista las entregas de su actividad', async () => {
    const servidor = await app();
    const respuesta = await servidor.inject({
      method: 'GET',
      url: `/api/v1/actividades/${ACTIVIDAD_ID}/entregas`,
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    await servidor.close();
  });
});
