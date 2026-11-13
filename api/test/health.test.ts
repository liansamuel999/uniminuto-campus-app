import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import { CHEQUEOS_OK, envPruebas } from './helpers.js';

describe('GET /health', () => {
  it('responde 200 cuando base de datos y almacenamiento están disponibles', async () => {
    const app = await construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });

    const respuesta = await app.inject({ method: 'GET', url: '/health' });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toEqual({
      estado: 'ok',
      db: 'ok',
      storage: 'ok',
      version: expect.any(String),
    });
    await app.close();
  });

  it('responde 503 si la base de datos falla', async () => {
    const app = await construirApp({
      env: envPruebas(),
      logger: false,
      chequeos: { baseDeDatos: async () => false, almacenamiento: async () => true },
    });

    const respuesta = await app.inject({ method: 'GET', url: '/health' });

    expect(respuesta.statusCode).toBe(503);
    expect(respuesta.json()).toMatchObject({ estado: 'degradado', db: 'error', storage: 'ok' });
    await app.close();
  });

  it('informa el almacenamiento como no configurado cuando no hay datalake', async () => {
    const app = await construirApp({
      env: envPruebas(),
      logger: false,
      chequeos: { baseDeDatos: async () => true },
    });

    const respuesta = await app.inject({ method: 'GET', url: '/health' });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ estado: 'ok', storage: 'no_configurado' });
    await app.close();
  });

  it('no exige autenticación', async () => {
    const app = await construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });
    const respuesta = await app.inject({ method: 'GET', url: '/health' });
    expect(respuesta.statusCode).toBe(200);
    await app.close();
  });
});
