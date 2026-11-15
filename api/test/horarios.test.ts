import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { RepositorioHorarios } from '../src/modules/academico/horarios.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const AULA_ID = '3f1c2b4a-1111-4a2b-9c3d-0000000000a1';

function repositorioFalso(): RepositorioHorarios {
  return {
    async miHorario() {
      return [
        {
          dia: 1,
          diaNombre: 'Lunes',
          horaInicio: '06:00',
          horaFin: '08:00',
          asignatura: 'Programación',
          codigo: 'IS-101',
          grupo: '01',
          periodo: '2026-2',
          salon: {
            codigo: 'A-101',
            tipo: 'AULA',
            capacidad: 30,
            piso: 1,
            edificio: 'Edificio A',
            edificioCodigo: 'A',
            sede: 'CALLE_80',
          },
          docente: 'Carolina Peña',
        },
      ];
    },
    async misAsignaturas() {
      return [
        {
          inscripcionId: '5c1e2b4a-7777-4c2b-9d3e-000000000007',
          grupoId: 'grupo-1',
          asignatura: 'Programación',
          codigo: 'IS-101',
          creditos: 4,
          grupo: '01',
          periodo: '2026-2',
          docente: 'Carolina Peña',
          aulaId: AULA_ID,
          evaluada: false,
          estudiantes: null,
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
    repositorioHorarios: repositorioFalso(),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-estudiante', secreto: SECRETO_PRUEBAS, roles });
}

describe('GET /api/v1/mi-horario', () => {
  it('exige autenticación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/mi-horario' });
    expect(respuesta.statusCode).toBe(401);
    await app.close();
  });

  it('devuelve los bloques con la ubicación del salón', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    expect(respuesta.json()[0]).toMatchObject({
      diaNombre: 'Lunes',
      horaInicio: '06:00',
      salon: { codigo: 'A-101', piso: 1, edificio: 'Edificio A' },
    });
    await app.close();
  });
});

describe('GET /api/v1/mis-asignaturas', () => {
  it('devuelve las asignaturas inscritas con el estado de la evaluación', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mis-asignaturas',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    expect(respuesta.json()[0]).toMatchObject({ asignatura: 'Programación', evaluada: false });
    await app.close();
  });
});
