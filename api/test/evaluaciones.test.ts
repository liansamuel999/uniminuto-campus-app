import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { RepositorioEvaluaciones } from '../src/modules/academico/evaluaciones.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const INSCRIPCION_ID = '5c1e2b4a-7777-4c2b-9d3e-000000000007';

const RESPUESTAS = {
  dominio: 5,
  claridad: 4,
  metodologia: 4,
  evaluacion: 5,
  acompanamiento: 4,
};

interface Capturas {
  evaluaciones: Array<{
    inscripcionId: string;
    respuestas: Record<string, number>;
    comentario?: string;
  }>;
}

function repositorioFalso(capturas: Capturas): RepositorioEvaluaciones {
  return {
    async crear(_uid, datos) {
      capturas.evaluaciones.push(datos);
      return { id: '00000000-0000-4000-8000-000000000001', enviadaEn: '2026-11-14T12:00:00.000Z' };
    },
    async resumen() {
      return [
        {
          docenteId: '9e1e2b4a-5555-4c2b-9d3e-000000000005',
          docente: 'Carolina Peña',
          evaluaciones: 3,
          criterios: { dominio: 4.67, claridad: 4.33, metodologia: 4, evaluacion: 4.33, acompanamiento: 4.67 },
          promedio: 4.4,
        },
      ];
    },
  };
}

async function crearApp(capturas: Capturas = { evaluaciones: [] }) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioEvaluaciones: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-estudiante', secreto: SECRETO_PRUEBAS, roles });
}

describe('POST /api/v1/evaluaciones-docentes (§4.2)', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/evaluaciones-docentes',
      payload: { inscripcionId: INSCRIPCION_ID, respuestas: RESPUESTAS },
    });
    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('rechaza criterios fuera de la escala 1–5', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/evaluaciones-docentes',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { inscripcionId: INSCRIPCION_ID, respuestas: { ...RESPUESTAS, claridad: 6 } },
    });
    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ codigo: 'DATOS_INVALIDOS' });
    await app.close();
  });

  it('exige los cinco criterios', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/evaluaciones-docentes',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { inscripcionId: INSCRIPCION_ID, respuestas: { dominio: 5, claridad: 4 } },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('registra la evaluación', async () => {
    const capturas: Capturas = { evaluaciones: [] };
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/evaluaciones-docentes',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { inscripcionId: INSCRIPCION_ID, respuestas: RESPUESTAS, comentario: 'Excelente clase' },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json()).toMatchObject({ enviadaEn: '2026-11-14T12:00:00.000Z' });
    expect(capturas.evaluaciones).toHaveLength(1);
    await app.close();
  });
});

describe('GET /api/v1/evaluaciones-docentes/resumen (D-49)', () => {
  it('solo el Admin Académico ve los agregados', async () => {
    const app = await crearApp();
    const estudiante = await app.inject({
      method: 'GET',
      url: '/api/v1/evaluaciones-docentes/resumen',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(estudiante.statusCode).toBe(403);

    const admin = await app.inject({
      method: 'GET',
      url: '/api/v1/evaluaciones-docentes/resumen',
      headers: { authorization: `Bearer ${await token(['ADMIN_ACADEMICO'])}` },
    });
    expect(admin.statusCode).toBe(200);
    expect(admin.json()[0]).toMatchObject({ docente: 'Carolina Peña', evaluaciones: 3, promedio: 4.4 });
    await app.close();
  });
});
