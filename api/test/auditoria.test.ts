import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import type { EventoAuditoria, FiltrosAuditoria, RepositorioAuditoria } from '../src/modules/auditoria/auditoria.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';
import { CHEQUEOS_OK, SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const EVENTO: EventoAuditoria = {
  id: '4f1c2b4a-2222-4a2b-9c3d-000000000002',
  timestamp: '2026-11-14T12:00:00.000Z',
  accion: 'CAMBIO_NOTA',
  recurso: 'calificacion:00000000-0000-4000-8000-000000000001',
  resultado: 'OK',
  actor: { id: '5f1c2b4a-3333-4a2b-9c3d-000000000003', nombre: 'Carolina Peña', correo: 'carolina@demo.uniminuto.test' },
};

function repositorioFalso(capturas: FiltrosAuditoria[]): RepositorioAuditoria {
  return {
    async listar(filtros) {
      capturas.push(filtros);
      return [EVENTO];
    },
    async acciones() {
      return ['ASIGNAR_DOCENTE', 'CAMBIO_NOTA', 'VALIDAR_ACCESO'];
    },
  };
}

async function crearApp(capturas: FiltrosAuditoria[] = []) {
  return construirApp({
    env: envPruebas(),
    logger: false,
    chequeos: CHEQUEOS_OK,
    repositorioAuditoria: repositorioFalso(capturas),
  });
}

async function token(roles: string[]): Promise<string> {
  return firmarTokenDev({ uid: 'uid-auditor', secreto: SECRETO_PRUEBAS, roles });
}

describe('auditoría (§8.1)', () => {
  it('solo el Auditor lee la bitácora', async () => {
    const app = await crearApp();
    const estudiante = await app.inject({
      method: 'GET',
      url: '/api/v1/auditoria',
      headers: { authorization: `Bearer ${await token(['ESTUDIANTE'])}` },
    });
    expect(estudiante.statusCode).toBe(403);

    const admin = await app.inject({
      method: 'GET',
      url: '/api/v1/auditoria',
      headers: { authorization: `Bearer ${await token(['ADMIN_ACADEMICO'])}` },
    });
    expect(admin.statusCode).toBe(403);
    await app.close();
  });

  it('aplica los filtros de fecha, acción, actor y límite', async () => {
    const capturas: FiltrosAuditoria[] = [];
    const app = await crearApp(capturas);
    const respuesta = await app.inject({
      method: 'GET',
      url:
        '/api/v1/auditoria?accion=CAMBIO_NOTA&limite=25'
        + '&desde=2026-11-01T00:00:00.000Z&hasta=2026-11-30T23:59:59.000Z'
        + '&actorId=5f1c2b4a-3333-4a2b-9c3d-000000000003',
      headers: { authorization: `Bearer ${await token(['AUDITOR'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toHaveLength(1);
    expect(capturas[0]).toMatchObject({ accion: 'CAMBIO_NOTA', limite: 25 });
    expect(capturas[0]?.desde).toBeInstanceOf(Date);
    await app.close();
  });

  it('usa un límite por defecto de 50 y rechaza valores fuera de rango', async () => {
    const capturas: FiltrosAuditoria[] = [];
    const app = await crearApp(capturas);
    const auditorToken = await token(['AUDITOR']);

    await app.inject({
      method: 'GET',
      url: '/api/v1/auditoria',
      headers: { authorization: `Bearer ${auditorToken}` },
    });
    expect(capturas[0]?.limite).toBe(50);

    const invalido = await app.inject({
      method: 'GET',
      url: '/api/v1/auditoria?limite=500',
      headers: { authorization: `Bearer ${auditorToken}` },
    });
    expect(invalido.statusCode).toBe(400);
    await app.close();
  });

  it('lista las acciones distintas para el filtro de la interfaz', async () => {
    const app = await crearApp();
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/auditoria/acciones',
      headers: { authorization: `Bearer ${await token(['AUDITOR'])}` },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toContain('CAMBIO_NOTA');
    await app.close();
  });
});
