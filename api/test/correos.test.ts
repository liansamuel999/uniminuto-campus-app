import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { CorreoSimulado, RepositorioCorreos } from '../src/modules/comunicacion/correos.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const AULA_ID = '3f1c2b4a-1111-4a2b-9c3d-0000000000a1';
const ANUNCIO_ID = 'anuncio-demo-1';

interface Capturas {
  replicas: Array<{ anuncioId: string; aulaId: string; asunto: string; cuerpo: string }>;
}

function repositorioFalso(capturas: Capturas): RepositorioCorreos {
  return {
    async replicar(_uid, anuncioId, aulaId, asunto, cuerpo) {
      capturas.replicas.push({ anuncioId, aulaId, asunto, cuerpo });
      return 3;
    },
    async listar(): Promise<CorreoSimulado[]> {
      return [
        {
          id: '00000000-0000-4000-8000-000000000001',
          asunto: 'Recordatorio de entrega',
          cuerpo: 'La entrega cierra el viernes.',
          creadoEn: '2026-11-13T00:00:00.000Z',
        },
      ];
    },
  };
}

async function crearApp(capturas: Capturas = { replicas: [] }) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioCorreos: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-docente', secreto: SECRETO_PRUEBAS, roles });
}

describe('POST /api/v1/anuncios/:id/replicar-correo (§6.2, D-48)', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/anuncios/${ANUNCIO_ID}/replicar-correo`,
      payload: { aulaId: AULA_ID, asunto: 'Aviso', cuerpo: 'Contenido' },
    });
    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('valida el cuerpo de la réplica', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/anuncios/${ANUNCIO_ID}/replicar-correo`,
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
      payload: { asunto: 'Aviso', cuerpo: 'Contenido' },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('replica el anuncio a los estudiantes y devuelve el número de correos', async () => {
    const capturas: Capturas = { replicas: [] };
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/anuncios/${ANUNCIO_ID}/replicar-correo`,
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
      payload: { aulaId: AULA_ID, asunto: 'Recordatorio', cuerpo: 'La entrega cierra el viernes.' },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toEqual({ anuncioId: ANUNCIO_ID, creados: 3 });
    expect(capturas.replicas).toEqual([
      {
        anuncioId: ANUNCIO_ID,
        aulaId: AULA_ID,
        asunto: 'Recordatorio',
        cuerpo: 'La entrega cierra el viernes.',
      },
    ]);
    await app.close();
  });
});

describe('GET /api/v1/correos-simulados', () => {
  it('devuelve la bandeja simulada del usuario', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/correos-simulados',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    expect(respuesta.json()[0]).toMatchObject({ asunto: 'Recordatorio de entrega' });
    await app.close();
  });
});
