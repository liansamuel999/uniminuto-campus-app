import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { EventoAcceso, RepositorioAcceso } from '../src/modules/acceso/acceso.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const CARNET_ID = '3f1c2b4a-1111-4a2b-9c3d-000000000001';

interface Capturas {
  eventos?: EventoAcceso[];
}

function repositorioFalso(capturas: Capturas): RepositorioAcceso {
  return {
    async listarRevocaciones() {
      return {
        version: 1_760_000_000_000,
        actualizadoEn: '2026-11-13T00:00:00.000Z',
        carnets: [CARNET_ID],
      };
    },
    async registrarAccesos(_uid, eventos) {
      capturas.eventos = eventos;
      return eventos.length;
    },
  };
}

async function crearApp(capturas: Capturas = {}) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioAcceso: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-demo', secreto: SECRETO_PRUEBAS, roles });
}

function evento(indice: number) {
  return {
    id: `00000000-0000-4000-8000-${String(indice).padStart(12, '0')}`,
    timestamp: '2026-11-13T01:02:03.000Z',
    carnetId: CARNET_ID,
    resultado: 'PERMITIDO',
  };
}

describe('GET /api/v1/acceso/revocaciones', () => {
  it('solo el rol Seguridad puede descargar la lista', async () => {
    const app = await crearApp();

    const estudiante = await app.inject({
      method: 'GET',
      url: '/api/v1/acceso/revocaciones',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(estudiante.statusCode).toBe(403);

    const seguridad = await app.inject({
      method: 'GET',
      url: '/api/v1/acceso/revocaciones',
      headers: { authorization: `Bearer ${await token(['SEGURIDAD'])}` },
    });
    expect(seguridad.statusCode).toBe(200);
    expect(seguridad.json()).toMatchObject({ carnets: [CARNET_ID] });

    await app.close();
  });
});

describe('POST /api/v1/auditoria/accesos', () => {
  it('registra el lote enviado por el validador', async () => {
    const capturas: Capturas = {};
    const app = await crearApp(capturas);

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/auditoria/accesos',
      headers: { authorization: `Bearer ${await token(['SEGURIDAD'])}` },
      payload: { eventos: [evento(1), evento(2)] },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json()).toEqual({ recibidos: 2, insertados: 2 });
    expect(capturas.eventos).toHaveLength(2);
    await app.close();
  });

  it('rechaza lotes de más de 100 eventos', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/auditoria/accesos',
      headers: { authorization: `Bearer ${await token(['SEGURIDAD'])}` },
      payload: { eventos: Array.from({ length: 101 }, (_, indice) => evento(indice)) },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ codigo: 'DATOS_INVALIDOS' });
    await app.close();
  });

  it('rechaza eventos con fecha inválida', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/auditoria/accesos',
      headers: { authorization: `Bearer ${await token(['SEGURIDAD'])}` },
      payload: { eventos: [{ ...evento(3), timestamp: 'ayer' }] },
    });

    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('un estudiante no puede escribir auditoría', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/auditoria/accesos',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { eventos: [evento(4)] },
    });

    expect(respuesta.statusCode).toBe(403);
    await app.close();
  });
});
