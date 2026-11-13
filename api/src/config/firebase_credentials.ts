import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Env } from './env.js';

/**
 * Raíz del paquete `api/`: vale tanto en `src/config/` (tsx) como en `dist/config/` (build).
 * Las rutas relativas de `api/.env` se resuelven contra esta carpeta, no contra el cwd del proceso,
 * para que `npm --prefix api run db:migrate` funcione desde la raíz del monorepo (D-59).
 */
export const RAIZ_API = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

/** Resuelve una ruta de credenciales relativa a `api/`. */
export function resolverRutaCredenciales(ruta: string): string {
  return path.isAbsolute(ruta) ? ruta : path.resolve(RAIZ_API, ruta);
}

/**
 * Devuelve el JSON de la cuenta de servicio de Firebase: bien el contenido de la variable
 * `FIREBASE_SERVICE_ACCOUNT`, bien el archivo indicado en `FIREBASE_SERVICE_ACCOUNT_PATH` (§7.2, D-59).
 *
 * El archivo nunca se versiona: `api/config/` está en `.gitignore`.
 */
export function leerCuentaDeServicioFirebase(env: Env): string | undefined {
  if (env.FIREBASE_SERVICE_ACCOUNT) {
    return env.FIREBASE_SERVICE_ACCOUNT;
  }
  if (!env.FIREBASE_SERVICE_ACCOUNT_PATH) {
    return undefined;
  }

  const ruta = resolverRutaCredenciales(env.FIREBASE_SERVICE_ACCOUNT_PATH);
  try {
    return readFileSync(ruta, 'utf8');
  } catch (error) {
    const detalle = error instanceof Error ? error.message : String(error);
    throw new Error(
      `No se pudo leer FIREBASE_SERVICE_ACCOUNT_PATH (${ruta}): ${detalle}. ` +
        'Comprueba que el archivo exista y que la ruta sea relativa a api/ o absoluta.',
    );
  }
}
