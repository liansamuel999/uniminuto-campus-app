import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { cargarEnv } from '../src/config/env.js';
import {
  leerCuentaDeServicioFirebase,
  resolverRutaCredenciales,
  RAIZ_API,
} from '../src/config/firebase_credentials.js';
import {
  crearVerificador,
  DevTokenVerifier,
  firmarTokenDev,
  VerificadorCompuesto,
  type IdentidadToken,
  type TokenVerifier,
} from '../src/modules/auth/verifier.js';
import { SECRETO_PRUEBAS, envPruebas } from './helpers.js';

const directorioTemporal = mkdtempSync(path.join(tmpdir(), 'campus-credenciales-'));
afterAll(() => rmSync(directorioTemporal, { recursive: true, force: true }));

describe('credenciales de Firebase (D-59)', () => {
  it('lee la cuenta de servicio desde una ruta absoluta', () => {
    const ruta = path.join(directorioTemporal, 'cuenta.json');
    writeFileSync(ruta, '{"project_id":"demo"}', 'utf8');

    const contenido = leerCuentaDeServicioFirebase(
      envPruebas({ FIREBASE_SERVICE_ACCOUNT_PATH: ruta }),
    );

    expect(contenido).toBe('{"project_id":"demo"}');
  });

  it('resuelve las rutas relativas contra api/, no contra el cwd', () => {
    expect(resolverRutaCredenciales('./config/firebase-service-account.json')).toBe(
      path.join(RAIZ_API, 'config', 'firebase-service-account.json'),
    );
    expect(path.basename(RAIZ_API)).toBe('api');
  });

  it('prefiere el JSON en variable de entorno sobre el archivo', () => {
    const contenido = leerCuentaDeServicioFirebase(
      envPruebas({
        FIREBASE_SERVICE_ACCOUNT: '{"project_id":"desde-env"}',
        FIREBASE_SERVICE_ACCOUNT_PATH: './no-existe.json',
      }),
    );

    expect(contenido).toBe('{"project_id":"desde-env"}');
  });

  it('falla con un mensaje claro si el archivo no existe', () => {
    const env = envPruebas({ FIREBASE_SERVICE_ACCOUNT_PATH: './config/no-existe.json' });

    expect(() => leerCuentaDeServicioFirebase(env)).toThrowError(
      /No se pudo leer FIREBASE_SERVICE_ACCOUNT_PATH/,
    );
  });
});

describe('crearVerificador', () => {
  it('en dev sin Firebase usa el verificador de tokens de prueba', async () => {
    const verificador = await crearVerificador(envPruebas());

    expect(verificador).toBeInstanceOf(DevTokenVerifier);
  });

  it('en producción exige una cuenta de servicio', async () => {
    const envProd = cargarEnv({
      ENTORNO: 'prod',
      DATABASE_URL: 'postgresql://root@localhost:26257/campus?sslmode=disable',
      CORS_ORIGINS: 'https://campus.demo.test',
    });

    await expect(crearVerificador(envProd)).rejects.toThrowError(
      /FIREBASE_SERVICE_ACCOUNT o FIREBASE_SERVICE_ACCOUNT_PATH/,
    );
  });
});

describe('VerificadorCompuesto', () => {
  const identidad: IdentidadToken = { uid: 'uid-real', roles: ['ESTUDIANTE'] };

  const rechaza: TokenVerifier = {
    verificar: async () => {
      throw new Error('no es de Firebase');
    },
  };
  const acepta: TokenVerifier = { verificar: async () => identidad };

  it('acepta si cualquiera de los verificadores valida el token', async () => {
    const compuesto = new VerificadorCompuesto([rechaza, acepta]);

    await expect(compuesto.verificar('token')).resolves.toEqual(identidad);
  });

  it('propaga el último error si ninguno lo valida', async () => {
    const compuesto = new VerificadorCompuesto([rechaza, rechaza]);

    await expect(compuesto.verificar('token')).rejects.toThrowError('no es de Firebase');
  });

  it('respeta el orden: Firebase primero y token de desarrollo como respaldo', async () => {
    const dev = new DevTokenVerifier(SECRETO_PRUEBAS);
    const compuesto = new VerificadorCompuesto([rechaza, dev]);
    const token = await firmarTokenDev({ uid: 'uid-demo', secreto: SECRETO_PRUEBAS });

    await expect(compuesto.verificar(token)).resolves.toMatchObject({ uid: 'uid-demo' });
  });
});
