import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { Grupo, Periodo, RepositorioAdminAcademico } from '../src/modules/admin/admin_academico.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const PERIODO_ID = '6f1c2b4a-4444-4a2b-9c3d-0000000000e4';
const GRUPO_ID = '7f1c2b4a-5555-4a2b-9c3d-0000000000f5';
const ASIGNATURA_ID = '8f1c2b4a-6666-4a2b-9c3d-0000000000a6';
const ESTUDIANTE_ID = '9f1c2b4a-7777-4a2b-9c3d-0000000000b7';

const PERIODO: Periodo = {
  id: PERIODO_ID,
  codigo: '2026-2',
  tipo: 'SEMESTRAL',
  fechaInicio: '2026-08-03',
  fechaFin: '2026-11-27',
  activo: true,
};

const GRUPO: Grupo = {
  id: GRUPO_ID,
  asignaturaId: ASIGNATURA_ID,
  asignatura: 'Programación I',
  codigoAsignatura: 'IS-101',
  periodoId: PERIODO_ID,
  periodo: '2026-2',
  docenteId: null,
  docente: null,
  numeroGrupo: '01',
  estudiantes: 3,
};

interface Capturas {
  periodos: unknown[];
  grupos: Array<{ uid: string; esAdmin: boolean; filtros: Record<string, unknown> }>;
  asignaciones: Array<{ id: string; datos: Record<string, unknown> }>;
  inscripciones: unknown[];
}

function repositorioFalso(capturas: Capturas): RepositorioAdminAcademico {
  return {
    async listarPeriodos() {
      return [PERIODO];
    },
    async crearPeriodo(datos) {
      capturas.periodos.push(datos);
      return { id: PERIODO_ID, ...datos };
    },
    async listarGrupos(uid, esAdmin, filtros) {
      capturas.grupos.push({ uid, esAdmin, filtros: filtros as Record<string, unknown> });
      return [GRUPO];
    },
    async actualizarGrupo(_uid, id, datos) {
      capturas.asignaciones.push({ id, datos: datos as Record<string, unknown> });
      return { ...GRUPO, docenteId: datos.docenteId ?? null };
    },
    async crearInscripcion(datos) {
      capturas.inscripciones.push(datos);
      return {
        id: '00000000-0000-4000-8000-000000000001',
        estudianteId: datos.estudianteId,
        estudiante: 'Juan Pablo Rojas',
        grupoId: datos.grupoId,
        asignatura: 'Programación I',
        grupo: '01',
        periodo: '2026-2',
        estado: 'ACTIVA',
      };
    },
    async listarUsuarios() {
      return [
        {
          id: ESTUDIANTE_ID,
          nombres: 'Juan Pablo',
          apellidos: 'Rojas',
          correo: 'juan.rojas@demo.uniminuto.test',
          documento: null,
          codigoInstitucional: 'UNI-001',
          roles: ['ESTUDIANTE'],
          programa: 'Ingeniería de Sistemas',
        },
      ];
    },
  } as unknown as RepositorioAdminAcademico;
}

async function crearApp(capturas: Capturas = { periodos: [], grupos: [], asignaciones: [], inscripciones: [] }) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioAdminAcademico: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-admin', secreto: SECRETO_PRUEBAS, roles });
}

describe('administración académica: RBAC (§5)', () => {
  it('el estudiante no puede leer el catálogo académico ni crear periodos', async () => {
    const app = await crearApp();
    const lectura = await app.inject({
      method: 'GET',
      url: '/api/v1/periodos',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(lectura.statusCode).toBe(403);

    const creacion = await app.inject({
      method: 'POST',
      url: '/api/v1/periodos',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
      payload: { codigo: '2027-1', tipo: 'SEMESTRAL', fechaInicio: '2027-01-20', fechaFin: '2027-05-20', activo: false },
    });
    expect(creacion.statusCode).toBe(403);
    await app.close();
  });

  it('el docente lee periodos y sus grupos, pero no crea grupos', async () => {
    const capturas: Capturas = { periodos: [], grupos: [], asignaciones: [], inscripciones: [] };
    const app = await crearApp(capturas);
    const docToken = await token(['DOCENTE']);

    const periodos = await app.inject({
      method: 'GET',
      url: '/api/v1/periodos',
      headers: { authorization: `Bearer ${docToken}` },
    });
    expect(periodos.statusCode).toBe(200);

    const grupos = await app.inject({
      method: 'GET',
      url: '/api/v1/grupos',
      headers: { authorization: `Bearer ${docToken}` },
    });
    expect(grupos.statusCode).toBe(200);
    expect(capturas.grupos[0]?.esAdmin).toBe(false);

    const creacion = await app.inject({
      method: 'POST',
      url: '/api/v1/grupos',
      headers: { authorization: `Bearer ${docToken}` },
      payload: { asignaturaId: ASIGNATURA_ID, periodoId: PERIODO_ID, numeroGrupo: '02' },
    });
    expect(creacion.statusCode).toBe(403);
    await app.close();
  });
});

describe('administración académica: operaciones del Admin Académico', () => {
  it('crea un periodo válido y rechaza códigos con formato inválido', async () => {
    const capturas: Capturas = { periodos: [], grupos: [], asignaciones: [], inscripciones: [] };
    const app = await crearApp(capturas);
    const adminToken = await token(['ADMIN_ACADEMICO']);

    const creado = await app.inject({
      method: 'POST',
      url: '/api/v1/periodos',
      headers: { authorization: `Bearer ${adminToken}` },
      payload: { codigo: '2027-1', tipo: 'SEMESTRAL', fechaInicio: '2027-01-20', fechaFin: '2027-05-20', activo: true },
    });
    expect(creado.statusCode).toBe(201);
    expect(capturas.periodos).toHaveLength(1);

    const invalido = await app.inject({
      method: 'POST',
      url: '/api/v1/periodos',
      headers: { authorization: `Bearer ${adminToken}` },
      payload: { codigo: '2027', tipo: 'SEMESTRAL', fechaInicio: '2027-01-20', fechaFin: '2027-05-20', activo: false },
    });
    expect(invalido.statusCode).toBe(400);
    await app.close();
  });

  it('asigna un docente a un grupo (auditoría ASIGNAR_DOCENTE en el repositorio)', async () => {
    const capturas: Capturas = { periodos: [], grupos: [], asignaciones: [], inscripciones: [] };
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'PUT',
      url: `/api/v1/grupos/${GRUPO_ID}`,
      headers: { authorization: `Bearer ${await token(['ADMIN_ACADEMICO'])}` },
      payload: { docenteId: '1f1c2b4a-8888-4a2b-9c3d-0000000000c8' },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(capturas.asignaciones[0]).toMatchObject({ id: GRUPO_ID });
    await app.close();
  });

  it('inscribe un estudiante y lista el catálogo de usuarios', async () => {
    const capturas: Capturas = { periodos: [], grupos: [], asignaciones: [], inscripciones: [] };
    const app = await crearApp(capturas);
    const adminToken = await token(['ADMIN_ACADEMICO']);

    const inscripcion = await app.inject({
      method: 'POST',
      url: '/api/v1/inscripciones',
      headers: { authorization: `Bearer ${adminToken}` },
      payload: { estudianteId: ESTUDIANTE_ID, grupoId: GRUPO_ID },
    });
    expect(inscripcion.statusCode).toBe(201);
    expect(capturas.inscripciones).toHaveLength(1);

    const usuarios = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?rol=ESTUDIANTE',
      headers: { authorization: `Bearer ${adminToken}` },
    });
    expect(usuarios.statusCode).toBe(200);
    expect(usuarios.json()[0]).toMatchObject({ correo: 'juan.rojas@demo.uniminuto.test' });
    await app.close();
  });
});
