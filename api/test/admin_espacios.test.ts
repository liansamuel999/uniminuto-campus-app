import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { RepositorioAdminEspacios } from '../src/modules/admin/admin_espacios.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const PISO_ID = '4f1c2b4a-2222-4a2b-9c3d-0000000000c2';
const SALON_ID = '5f1c2b4a-3333-4a2b-9c3d-0000000000d3';
const GRUPO_ID = '7f1c2b4a-5555-4a2b-9c3d-0000000000f5';
const HORARIO_ID = '2f1c2b4a-9999-4a2b-9c3d-0000000000e9';

function repositorioFalso(): RepositorioAdminEspacios {
  return {
    async crearSalon(datos) {
      return { id: SALON_ID, pisoId: datos.pisoId, codigo: datos.codigo, tipo: datos.tipo, capacidad: datos.capacidad };
    },
    async listarHorarios() {
      return [
        {
          id: HORARIO_ID,
          grupoId: GRUPO_ID,
          asignatura: 'Programación I',
          grupo: '01',
          periodo: '2026-2',
          salonId: SALON_ID,
          salon: 'A-101',
          diaSemana: 1,
          horaInicio: '07:00',
          horaFin: '09:00',
        },
      ];
    },
    async crearHorario(datos) {
      return {
        id: HORARIO_ID,
        grupoId: datos.grupoId,
        asignatura: 'Programación I',
        grupo: '01',
        periodo: '2026-2',
        salonId: datos.salonId,
        salon: 'A-101',
        diaSemana: datos.diaSemana,
        horaInicio: datos.horaInicio,
        horaFin: datos.horaFin,
      };
    },
    async eliminarHorario() {
      return false;
    },
  } as unknown as RepositorioAdminEspacios;
}

async function crearApp() {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioAdminEspacios: repositorioFalso(),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-espacios', secreto: SECRETO_PRUEBAS, roles });
}

describe('administración de espacios (§5)', () => {
  it('el Admin Académico también administra los salones (rol de espacios absorbido)', async () => {
    const app = await crearApp();
    const payload = { pisoId: PISO_ID, codigo: 'A-111', tipo: 'AULA', capacidad: 35 };

    const academico = await app.inject({
      method: 'POST',
      url: '/api/v1/espacios/salones',
      headers: { authorization: `Bearer ${await token(['ADMIN_ACADEMICO'])}` },
      payload,
    });
    expect(academico.statusCode).toBe(201);

    const docente = await app.inject({
      method: 'POST',
      url: '/api/v1/espacios/salones',
      headers: { authorization: `Bearer ${await token(['DOCENTE'])}` },
      payload,
    });
    expect(docente.statusCode).toBe(403);
    await app.close();
  });

  it('valida la capacidad y el tipo de salón', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/espacios/salones',
      headers: { authorization: `Bearer ${await token(['ADMIN_ESPACIOS'])}` },
      payload: { pisoId: PISO_ID, codigo: 'A-112', tipo: 'AULA', capacidad: 0 },
    });
    expect(respuesta.statusCode).toBe(400);
    await app.close();
  });

  it('asigna un salón a un horario y valida la hora', async () => {
    const app = await crearApp();
    const espaciosToken = await token(['ADMIN_ESPACIOS']);

    const creado = await app.inject({
      method: 'POST',
      url: '/api/v1/horarios',
      headers: { authorization: `Bearer ${espaciosToken}` },
      payload: { grupoId: GRUPO_ID, salonId: SALON_ID, diaSemana: 1, horaInicio: '07:00', horaFin: '09:00' },
    });
    expect(creado.statusCode).toBe(201);

    const invalido = await app.inject({
      method: 'POST',
      url: '/api/v1/horarios',
      headers: { authorization: `Bearer ${espaciosToken}` },
      payload: { grupoId: GRUPO_ID, salonId: SALON_ID, diaSemana: 1, horaInicio: '25:00', horaFin: '09:00' },
    });
    expect(invalido.statusCode).toBe(400);
    await app.close();
  });

  it('el Admin Académico lee y administra los horarios', async () => {
    const app = await crearApp();
    const academicoToken = await token(['ADMIN_ACADEMICO']);

    const lectura = await app.inject({
      method: 'GET',
      url: '/api/v1/horarios',
      headers: { authorization: `Bearer ${academicoToken}` },
    });
    expect(lectura.statusCode).toBe(200);

    // Ahora tiene permiso de administrarlos: el repo falso dice que no existe → 404.
    const borrado = await app.inject({
      method: 'DELETE',
      url: `/api/v1/horarios/${HORARIO_ID}`,
      headers: { authorization: `Bearer ${academicoToken}` },
    });
    expect(borrado.statusCode).toBe(404);
    await app.close();
  });

  it('devuelve 404 cuando el horario no existe', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'DELETE',
      url: `/api/v1/horarios/${HORARIO_ID}`,
      headers: { authorization: `Bearer ${await token(['ADMIN_ESPACIOS'])}` },
    });
    expect(respuesta.statusCode).toBe(404);
    await app.close();
  });
});
