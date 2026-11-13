import { describe, expect, it } from 'vitest';
import { construirApp } from '../src/app.js';
import { CHEQUEOS_OK, envPruebas } from './helpers.js';

describe('CORS (D-22, D-63)', () => {
  it('acepta el origen configurado', async () => {
    const app = await construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });
    const respuesta = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'http://localhost:5173' },
    });

    expect(respuesta.headers['access-control-allow-origin']).toBe('http://localhost:5173');
    await app.close();
  });

  it('en dev acepta cualquier puerto de localhost (flutter run elige uno aleatorio)', async () => {
    const app = await construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });
    const respuesta = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'http://localhost:54321' },
    });

    expect(respuesta.headers['access-control-allow-origin']).toBe('http://localhost:54321');
    await app.close();
  });

  it('rechaza un origen externo desconocido', async () => {
    const app = await construirApp({ env: envPruebas(), logger: false, chequeos: CHEQUEOS_OK });
    const respuesta = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'https://sitio-externo.example' },
    });

    expect(respuesta.headers['access-control-allow-origin']).toBeUndefined();
    await app.close();
  });
});
