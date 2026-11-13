import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const crearApp = () => construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });

describe('autenticación por ID Token', () => {
  it('rechaza sin cabecera Authorization', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/sesion' });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json()).toEqual({
      codigo: 'NO_AUTORIZADO',
      mensaje: expect.stringContaining('Authorization'),
    });
    await app.close();
  });

  it('rechaza un token con formato inválido', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/sesion',
      headers: { authorization: 'Bearer esto-no-es-un-jwt' },
    });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json()).toMatchObject({ codigo: 'NO_AUTORIZADO' });
    await app.close();
  });

  it('rechaza un token firmado con otro secreto', async () => {
    const app = await crearApp();
    const token = await firmarTokenDev({ uid: 'uid-1', secreto: 'otro-secreto-distinto-1234567890' });
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/sesion',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('acepta un token de desarrollo válido y devuelve uid y roles', async () => {
    const app = await crearApp();
    const token = await firmarTokenDev({
      uid: 'uid-demo-docente',
      secreto: SECRETO_PRUEBAS,
      roles: ['DOCENTE'],
    });

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/sesion',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toEqual({ uid: 'uid-demo-docente', roles: ['DOCENTE'] });
    await app.close();
  });

  it('aplica la guarda de roles: 403 cuando el rol no está en los claims', async () => {
    const app = await construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });
    app.get(
      '/api/v1/solo-seguridad',
      { preHandler: [app.autenticar, app.requerirRoles('SEGURIDAD')] },
      async () => ({ permitido: true }),
    );

    const tokenEstudiante = await firmarTokenDev({
      uid: 'uid-demo-estudiante',
      secreto: SECRETO_PRUEBAS,
      roles: ['ESTUDIANTE'],
    });

    const denegado = await app.inject({
      method: 'GET',
      url: '/api/v1/solo-seguridad',
      headers: { authorization: `Bearer ${tokenEstudiante}` },
    });
    expect(denegado.statusCode).toBe(403);
    expect(denegado.json()).toMatchObject({ codigo: 'PROHIBIDO' });

    const tokenSeguridad = await firmarTokenDev({
      uid: 'uid-demo-seguridad',
      secreto: SECRETO_PRUEBAS,
      roles: ['SEGURIDAD'],
    });
    const permitido = await app.inject({
      method: 'GET',
      url: '/api/v1/solo-seguridad',
      headers: { authorization: `Bearer ${tokenSeguridad}` },
    });
    expect(permitido.statusCode).toBe(200);
    await app.close();
  });

  it('devuelve 404 uniforme en rutas inexistentes', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/no-existe' });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ codigo: 'NO_ENCONTRADO' });
    await app.close();
  });
});
