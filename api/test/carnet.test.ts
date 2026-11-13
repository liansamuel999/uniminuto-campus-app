import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import { AppError } from '../src/lib/errors.js';
import type { RepositorioCarnet, ResumenCarnet } from '../src/modules/carnet/carnet.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const UID = 'uid-demo-estudiante';
const DISPOSITIVO_ID = '5a0e7e6e-2222-4b3c-8d4e-000000000002';

const resumen: ResumenCarnet = {
  carnet: {
    id: '3f1c2b4a-1111-4a2b-9c3d-000000000001',
    codigoBarras: 'UNI-20261001',
    estado: 'ACTIVO',
    vigenteHasta: '2027-11-13T00:00:00.000Z',
  },
  dispositivo: {
    id: DISPOSITIVO_ID,
    nombre: 'Pixel de prueba',
    vinculadoEn: '2026-11-13T00:00:00.000Z',
  },
  certificado: {
    jwt: 'cabecera.payload.firma',
    kid: 'inst-2026-11-d93e89',
    emitidoEn: '2026-11-13T00:00:00.000Z',
    expiraEn: '2026-12-13T00:00:00.000Z',
  },
};

interface Capturas {
  revocacion?: { dispositivoId: string; puedeRevocarAjeno: boolean };
  vinculacion?: { nombre: string; jwk: unknown };
}

function repositorioFalso(capturas: Capturas): RepositorioCarnet {
  return {
    async obtenerResumen(uid) {
      return uid === UID ? resumen : null;
    },
    async vincular(uid, datos) {
      capturas.vinculacion = { nombre: datos.nombreDispositivo, jwk: datos.clavePublicaJwk };
      return resumen;
    },
    async renovar(uid) {
      if (uid !== UID) throw new AppError('CONFLICTO', 'sin dispositivo', 409);
      return resumen;
    },
    async revocar(uid, dispositivoId, puedeRevocarAjeno) {
      capturas.revocacion = { dispositivoId, puedeRevocarAjeno };
    },
  };
}

async function clavePublicaValida(): Promise<Record<string, string>> {
  const par = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
  const jwk = (await crypto.subtle.exportKey('jwk', par.publicKey)) as Record<string, string>;
  return { kty: 'EC', crv: 'P-256', x: jwk['x']!, y: jwk['y']! };
}

async function crearApp(capturas: Capturas = {}) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioCarnet: repositorioFalso(capturas),
  });
}

async function token(roles: string[] = ['ESTUDIANTE'], uid = UID): Promise<string> {
  return firmarTokenDev({ uid, secreto: SECRETO_PRUEBAS, roles });
}

describe('GET /api/v1/carnet/mio', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/carnet/mio' });
    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('devuelve carnet, dispositivo activo y certificado', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/carnet/mio',
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      carnet: { codigoBarras: 'UNI-20261001', estado: 'ACTIVO' },
      dispositivo: { nombre: 'Pixel de prueba' },
      certificado: { kid: 'inst-2026-11-d93e89' },
    });
    await app.close();
  });
});

describe('POST /api/v1/dispositivos', () => {
  it('vincula un dispositivo con una JWK EC P-256', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/dispositivos',
      headers: { authorization: `Bearer ${await token()}` },
      payload: { nombreDispositivo: 'Pixel de prueba', clavePublicaJwk: await clavePublicaValida() },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(capturas.vinculacion?.nombre).toBe('Pixel de prueba');
    await app.close();
  });

  it('rechaza claves que no son EC P-256', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/dispositivos',
      headers: { authorization: `Bearer ${await token()}` },
      payload: {
        nombreDispositivo: 'Portátil',
        clavePublicaJwk: { kty: 'RSA', n: 'abc', e: 'AQAB' },
      },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ codigo: 'DATOS_INVALIDOS' });
    await app.close();
  });
});

describe('DELETE /api/v1/dispositivos/:id', () => {
  it('el dueño revoca su propio dispositivo', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'DELETE',
      url: `/api/v1/dispositivos/${DISPOSITIVO_ID}`,
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(capturas.revocacion).toEqual({
      dispositivoId: DISPOSITIVO_ID,
      puedeRevocarAjeno: false,
    });
    await app.close();
  });

  it('Soporte puede revocar el dispositivo de otro', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'DELETE',
      url: `/api/v1/dispositivos/${DISPOSITIVO_ID}`,
      headers: { authorization: `Bearer ${await token(['SOPORTE'], 'uid-soporte')}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(capturas.revocacion?.puedeRevocarAjeno).toBe(true);
    await app.close();
  });

  it('valida el formato del id', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'DELETE',
      url: '/api/v1/dispositivos/no-es-uuid',
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });
});

describe('POST /api/v1/dispositivos/renovar-certificado', () => {
  it('renueva el certificado del dispositivo activo', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/dispositivos/renovar-certificado',
      headers: { authorization: `Bearer ${await token()}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ certificado: { kid: 'inst-2026-11-d93e89' } });
    await app.close();
  });

  it('acepta Content-Type JSON con cuerpo vacío (D-64)', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/dispositivos/renovar-certificado',
      headers: {
        authorization: `Bearer ${await token()}`,
        'content-type': 'application/json',
      },
    });

    expect(respuesta.statusCode).toBe(200);
    await app.close();
  });
});
