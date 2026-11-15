import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { FilaCalificacion, RepositorioCalificaciones } from '../src/modules/calificaciones/calificaciones.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const AULA_ID = '3f1c2b4a-1111-4a2b-9c3d-0000000000a1';
const ACTIVIDAD_ID = '9e1e2b4a-5555-4c2b-9d3e-000000000005';
const INSCRIPCION_ID = '5c1e2b4a-7777-4c2b-9d3e-000000000007';

interface Capturas {
  calificaciones: Array<{ actividadId: string; inscripcionId: string; nota: number; retroalimentacion?: string }>;
}

function repositorioFalso(capturas: Capturas): RepositorioCalificaciones {
  return {
    async calificar(_uid, datos) {
      capturas.calificaciones.push(datos);
      return { nota: datos.nota, notaCorte: 4.25 };
    },
    async listar(): Promise<FilaCalificacion[]> {
      return [
        {
          inscripcionId: INSCRIPCION_ID,
          estudiante: 'Juan Pablo Rojas',
          actividadId: ACTIVIDAD_ID,
          titulo: 'Taller de la unidad 1',
          notaMaxima: 5,
          nota: 4.2,
          retroalimentacion: 'Buen trabajo',
        },
      ];
    },
  };
}

async function crearApp(capturas: Capturas = { calificaciones: [] }) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioCalificaciones: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-docente', secreto: SECRETO_PRUEBAS, roles });
}

describe('PUT /api/v1/calificaciones (§6.4)', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/calificaciones',
      payload: { actividadId: ACTIVIDAD_ID, inscripcionId: INSCRIPCION_ID, nota: 4 },
    });
    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('rechaza una nota fuera del rango 0–5', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/calificaciones',
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
      payload: { actividadId: ACTIVIDAD_ID, inscripcionId: INSCRIPCION_ID, nota: 6 },
    });
    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ codigo: 'DATOS_INVALIDOS' });
    await app.close();
  });

  it('rechaza campos desconocidos', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/calificaciones',
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
      payload: {
        actividadId: ACTIVIDAD_ID,
        inscripcionId: INSCRIPCION_ID,
        nota: 4,
        estudianteUid: 'otro',
      },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('registra la calificación y devuelve la nota del corte', async () => {
    const capturas: Capturas = { calificaciones: [] };
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'PUT',
      url: '/api/v1/calificaciones',
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
      payload: {
        actividadId: ACTIVIDAD_ID,
        inscripcionId: INSCRIPCION_ID,
        nota: 4.5,
        retroalimentacion: 'Buen trabajo',
      },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toEqual({ nota: 4.5, notaCorte: 4.25 });
    expect(capturas.calificaciones).toEqual([
      { actividadId: ACTIVIDAD_ID, inscripcionId: INSCRIPCION_ID, nota: 4.5, retroalimentacion: 'Buen trabajo' },
    ]);
    await app.close();
  });
});

describe('GET /api/v1/aulas/:id/calificaciones', () => {
  it('devuelve las notas del aula al docente', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aulas/${AULA_ID}/calificaciones`,
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    expect(respuesta.json()[0]).toMatchObject({ nota: 4.2, notaMaxima: 5 });
    await app.close();
  });

  it('valida el uuid del aula', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/aulas/no-es-uuid/calificaciones',
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });
});
