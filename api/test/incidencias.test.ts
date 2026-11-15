import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { Incidencia, RepositorioIncidencias } from '../src/modules/incidencias/incidencias.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const INCIDENCIA_ID = '3f1c2b4a-1111-4a2b-9c3d-000000000001';

const INCIDENCIA: Incidencia = {
  id: INCIDENCIA_ID,
  descripcion: 'El lector del Edificio B no reconoce el QR del carnet',
  estado: 'ABIERTA',
  resolucion: null,
  creadaEn: '2026-11-14T12:00:00.000Z',
  actualizadaEn: '2026-11-14T12:00:00.000Z',
  usuario: 'Juan Pablo Rojas',
  atendidaPor: null,
};

interface Capturas {
  creadas: Array<{ uid: string; descripcion: string }>;
  propias: string[];
  porEstado: Array<string | null>;
  actualizadas: Array<{ uid: string; id: string; datos: Record<string, unknown> }>;
}

function repositorioFalso(capturas: Capturas): RepositorioIncidencias {
  return {
    async crear(uid, descripcion) {
      capturas.creadas.push({ uid, descripcion });
      return { ...INCIDENCIA, descripcion };
    },
    async listarPropias(uid) {
      capturas.propias.push(uid);
      return [INCIDENCIA];
    },
    async listarPorEstado(estado) {
      capturas.porEstado.push(estado ?? null);
      return [{ ...INCIDENCIA, estado: estado ?? 'ABIERTA' }];
    },
    async actualizar(uid, id, datos) {
      capturas.actualizadas.push({ uid, id, datos: datos as Record<string, unknown> });
      return { ...INCIDENCIA, estado: datos.estado, resolucion: datos.resolucion ?? null };
    },
  };
}

async function crearApp(capturas: Capturas) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioIncidencias: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-usuario', secreto: SECRETO_PRUEBAS, roles });
}

function capturasVacias(): Capturas {
  return { creadas: [], propias: [], porEstado: [], actualizadas: [] };
}

describe('incidencias (§5, D-50)', () => {
  it('cualquier rol autenticado reporta una incidencia', async () => {
    const capturas = capturasVacias();
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/incidencias',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { descripcion: 'La impresora del piso 2 no responde' },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(capturas.creadas).toHaveLength(1);
    expect(respuesta.json()).toMatchObject({ estado: 'ABIERTA' });
    await app.close();
  });

  it('rechaza descripciones demasiado cortas', async () => {
    const app = await crearApp(capturasVacias());
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/incidencias',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { descripcion: 'ayuda' },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('cada usuario ve solo sus incidencias y Soporte ve todas con filtro de estado', async () => {
    const capturas = capturasVacias();
    const app = await crearApp(capturas);

    const estudiante = await app.inject({
      method: 'GET',
      url: '/api/v1/incidencias',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(estudiante.statusCode).toBe(200);
    expect(capturas.propias).toHaveLength(1);

    const soporte = await app.inject({
      method: 'GET',
      url: '/api/v1/incidencias?estado=EN_PROCESO',
      headers: { authorization: `Bearer ${await token(['SOPORTE'])}` },
    });
    expect(soporte.statusCode).toBe(200);
    expect(capturas.porEstado).toEqual(['EN_PROCESO']);
    await app.close();
  });

  it('solo Soporte cambia el estado de una incidencia', async () => {
    const capturas = capturasVacias();
    const app = await crearApp(capturas);
    const payload = { estado: 'RESUELTA', resolucion: 'Se reinició el lector' };

    const estudiante = await app.inject({
      method: 'PUT',
      url: `/api/v1/incidencias/${INCIDENCIA_ID}`,
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload,
    });
    expect(estudiante.statusCode).toBe(403);

    const soporte = await app.inject({
      method: 'PUT',
      url: `/api/v1/incidencias/${INCIDENCIA_ID}`,
      headers: { authorization: `Bearer ${await token(['SOPORTE'])}` },
      payload,
    });
    expect(soporte.statusCode).toBe(200);
    expect(capturas.actualizadas[0]?.datos).toMatchObject({ estado: 'RESUELTA' });
    await app.close();
  });

  it('valida el estado en la actualización', async () => {
    const app = await crearApp(capturasVacias());
    const respuesta = await app.inject({
      method: 'PUT',
      url: `/api/v1/incidencias/${INCIDENCIA_ID}`,
      headers: { authorization: `Bearer ${await token(['SOPORTE'])}` },
      payload: { estado: 'INVENTADO' },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });
});
