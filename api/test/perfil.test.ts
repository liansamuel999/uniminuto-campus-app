import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { CambiosPerfil, PerfilUsuario, RepositorioPerfil } from '../src/modules/academico/perfil.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const UID = 'uid-demo-estudiante';

const perfilBase: PerfilUsuario = {
  id: '11111111-1111-1111-1111-111111111111',
  nombres: 'Juan Pablo',
  apellidos: 'Rojas Méndez',
  correo: 'juan.rojas@demo.uniminuto.test',
  documento: '1001001001',
  codigoInstitucional: '20261001',
  fotoKey: null,
  estado: 'ACTIVO',
  programa: { id: '22222222-2222-2222-2222-222222222222', nombre: 'Ingeniería de Sistemas' },
  roles: ['ESTUDIANTE'],
};

function repositorioFalso(): RepositorioPerfil {
  return {
    async obtenerPorUid(uid) {
      return uid === UID ? perfilBase : null;
    },
    async actualizarPorUid(uid, cambios: CambiosPerfil) {
      if (uid !== UID) return null;
      return { ...perfilBase, ...cambios };
    },
  };
}

async function crearApp() {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioPerfil: repositorioFalso(),
  });
}

async function tokenValido(uid = UID): Promise<string> {
  return firmarTokenDev({ uid, secreto: SECRETO_PRUEBAS, roles: ['ESTUDIANTE'] });
}

describe('GET /api/v1/mi-perfil', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/mi-perfil' });

    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('devuelve el perfil con roles y programa', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-perfil',
      headers: { authorization: `Bearer ${await tokenValido()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      correo: 'juan.rojas@demo.uniminuto.test',
      programa: { nombre: 'Ingeniería de Sistemas' },
      roles: ['ESTUDIANTE'],
    });
    await app.close();
  });

  it('devuelve 404 si el uid no está registrado en la base', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-perfil',
      headers: { authorization: `Bearer ${await tokenValido('uid-sin-registro')}` },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ codigo: 'NO_ENCONTRADO' });
    await app.close();
  });
});

describe('PUT /api/v1/mi-perfil', () => {
  it('actualiza nombres y apellidos propios', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/mi-perfil',
      headers: { authorization: `Bearer ${await tokenValido()}` },
      payload: { nombres: 'Juan P.', apellidos: 'Rojas' },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ nombres: 'Juan P.', apellidos: 'Rojas' });
    await app.close();
  });

  it('rechaza campos que no se pueden editar', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/mi-perfil',
      headers: { authorization: `Bearer ${await tokenValido()}` },
      payload: { correo: 'otro@demo.uniminuto.test' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ codigo: 'DATOS_INVALIDOS' });
    await app.close();
  });

  it('valida el formato de la foto del carnet', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/mi-perfil',
      headers: { authorization: `Bearer ${await tokenValido()}` },
      payload: { fotoKey: 'https://ejemplo.test/foto.jpg' },
    });

    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });
});
