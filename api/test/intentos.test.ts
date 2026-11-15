import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { RepositorioCuestionarios } from '../src/modules/actividades/cuestionarios.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const CUESTIONARIO_ID = '9e1e2b4a-5555-4c2b-9d3e-000000000005';

function repositorioFalso(): RepositorioCuestionarios {
  return {
    async obtener() {
      throw new Error('no usado en esta prueba');
    },
    async responder() {
      throw new Error('no usado en esta prueba');
    },
    async listarIntentos() {
      return [
        {
          estudiante: 'Juan Pablo Rojas',
          puntaje: 4.33,
          enviadoEn: '2026-11-13T10:00:00.000Z',
          respuestas: { 'pregunta-1': ['00000000-0000-4000-8000-000000000001'] },
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
    repositorioCuestionarios: repositorioFalso(),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-docente', secreto: SECRETO_PRUEBAS, roles });
}

describe('GET /api/v1/cuestionarios/:id/intentos (docente)', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/cuestionarios/${CUESTIONARIO_ID}/intentos`,
    });
    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('devuelve los intentos con puntaje y respuestas', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/cuestionarios/${CUESTIONARIO_ID}/intentos`,
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    expect(respuesta.json()[0]).toMatchObject({ estudiante: 'Juan Pablo Rojas', puntaje: 4.33 });
    await app.close();
  });

  it('valida el uuid del cuestionario', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/cuestionarios/no-es-uuid/intentos',
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });
});
