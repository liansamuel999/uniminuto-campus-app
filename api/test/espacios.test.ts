import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { RepositorioEspacios } from '../src/modules/espacios/espacios.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const EDIFICIO_ID = '3f1c2b4a-1111-4a2b-9c3d-0000000000b1';
const PISO_ID = '4f1c2b4a-2222-4a2b-9c3d-0000000000c2';

function repositorioFalso(): RepositorioEspacios {
  return {
    async edificios() {
      return [{ id: EDIFICIO_ID, codigo: 'A', nombre: 'Edificio A', sede: 'CALLE_80', pisos: 2 }];
    },
    async pisos(edificioId) {
      if (edificioId !== EDIFICIO_ID) return null;
      return [{ id: PISO_ID, numero: 1, tipo: 'ESTUDIANTIL', salones: 3 }];
    },
    async salones(pisoId) {
      if (pisoId !== PISO_ID) return null;
      return [{ id: '5f1c2b4a-3333-4a2b-9c3d-0000000000d3', codigo: 'A-101', tipo: 'AULA', capacidad: 30 }];
    },
    async salonesTodos() {
      return [
        {
          id: '5f1c2b4a-3333-4a2b-9c3d-0000000000d3',
          codigo: 'A-101',
          tipo: 'AULA',
          capacidad: 30,
          piso: 1,
          edificio: 'Edificio A',
          edificioCodigo: 'A',
        },
      ];
    },
  };
}

async function crearApp() {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioEspacios: repositorioFalso(),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-demo', secreto: SECRETO_PRUEBAS, roles });
}

describe('jerarquía del campus (§4.3, §7.7)', () => {
  it('lista los edificios para cualquier autenticado', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/espacios/edificios',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()[0]).toMatchObject({ codigo: 'A', sede: 'CALLE_80' });
    await app.close();
  });

  it('lista los pisos del edificio', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/espacios/edificios/${EDIFICIO_ID}/pisos`,
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()[0]).toMatchObject({ numero: 1, tipo: 'ESTUDIANTIL' });
    await app.close();
  });

  it('devuelve 404 si el edificio no existe', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/espacios/edificios/00000000-0000-4000-8000-000000000000/pisos',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(respuesta.statusCode).toBe(404);
    await app.close();
  });

  it('lista los salones del piso y valida el uuid', async () => {
    const app = await crearApp();
    const salones = await app.inject({
      method: 'GET',
      url: `/api/v1/espacios/pisos/${PISO_ID}/salones`,
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(salones.statusCode).toBe(200);
    expect(salones.json()[0]).toMatchObject({ codigo: 'A-101', capacidad: 30 });

    const invalido = await app.inject({
      method: 'GET',
      url: '/api/v1/espacios/pisos/no-es-uuid/salones',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(invalido.statusCode).toBe(400);
    await app.close();
  });

  it('lista todos los salones con su ubicación plana', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/espacios/salones',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()[0]).toMatchObject({ codigo: 'A-101', piso: 1, edificioCodigo: 'A' });
    await app.close();
  });
});
