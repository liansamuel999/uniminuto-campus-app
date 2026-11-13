import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Env } from './env.js';

/** JWK (EC P-256) de una clave. */
export interface JwkEc {
  kty: 'EC';
  crv: 'P-256';
  x: string;
  y: string;
  d?: string;
  kid?: string;
  alg?: string;
  use?: string;
}

export interface ClaveInstitucional {
  kid: string;
  privada: JwkEc;
  publica: JwkEc;
}

const RAIZ_API = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function resolverRuta(ruta: string): string {
  return path.isAbsolute(ruta) ? ruta : path.resolve(RAIZ_API, ruta);
}

function leerArchivo(ruta: string): string {
  try {
    return readFileSync(resolverRuta(ruta), 'utf8');
  } catch (error) {
    const detalle = error instanceof Error ? error.message : String(error);
    throw new Error(`No se pudo leer la clave institucional (${ruta}): ${detalle}`);
  }
}

/**
 * Carga el par institucional ES256 generado por `infra/scripts/generate-keys.mjs` (D-25, D-60).
 * Acepta el archivo completo `{ kid, privada, publica }` o un JWK privado suelto (Render).
 */
export function leerClaveInstitucional(env: Env): ClaveInstitucional {
  const crudo = env.INSTITUTION_PRIVATE_KEY
    ? env.INSTITUTION_PRIVATE_KEY
    : env.INSTITUTION_PRIVATE_KEY_PATH
      ? leerArchivo(env.INSTITUTION_PRIVATE_KEY_PATH)
      : undefined;

  if (!crudo) {
    throw new Error(
      'Faltan INSTITUTION_PRIVATE_KEY o INSTITUTION_PRIVATE_KEY_PATH: sin clave institucional no se pueden emitir certificados de carnet',
    );
  }

  let contenido: unknown;
  try {
    contenido = JSON.parse(crudo);
  } catch {
    throw new Error('La clave institucional no es un JSON válido');
  }

  const objeto = contenido as Record<string, unknown>;
  const envuelto = 'privada' in objeto && 'publica' in objeto;
  const privada = (envuelto ? (objeto['privada'] as JwkEc) : (objeto as unknown as JwkEc)) ?? null;
  const publica = envuelto ? (objeto['publica'] as JwkEc) : undefined;
  const kid = env.INSTITUTION_KID ?? (objeto['kid'] as string | undefined) ?? privada?.kid;

  if (!privada || privada.kty !== 'EC' || privada.crv !== 'P-256' || !privada.d || !privada.x || !privada.y) {
    throw new Error('La clave privada institucional no es una JWK EC P-256 completa');
  }
  if (!kid) {
    throw new Error('Falta INSTITUTION_KID (o el campo kid del archivo de claves)');
  }

  const publicaDerivada: JwkEc = publica ?? {
    kty: 'EC',
    crv: 'P-256',
    x: privada.x,
    y: privada.y,
  };

  return { kid, privada, publica: { ...publicaDerivada, kid, alg: 'ES256', use: 'sig' } };
}
