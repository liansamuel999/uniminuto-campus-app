#!/usr/bin/env node
/**
 * Genera el par de claves institucional ES256 del carnet (§6.1, D-25).
 *
 *   - Privada: `infra/keys/institution_private.jwk.json` (ignorada por git; nunca se versiona).
 *   - Pública: `app/assets/keys/institution_jwks.json` (JWKS público, se versiona y se embebe en
 *     el build del validador; admite varios `kid` para poder rotar).
 *
 * Uso:
 *   node infra/scripts/generate-keys.mjs            # crea el par si no existe
 *   node infra/scripts/generate-keys.mjs --force    # rota: crea un kid nuevo y conserva el anterior
 *
 * La firma se hace en el backend con la clave privada; el teléfono solo recibe certificados
 * firmados y por eso la clave privada institucional jamás sale de la API.
 */
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const DIRECTORIO_CLAVES = path.join(RAIZ, 'infra', 'keys');
const RUTA_PRIVADA = path.join(DIRECTORIO_CLAVES, 'institution_private.jwk.json');
const RUTA_PUBLICA = path.join(RAIZ, 'app', 'assets', 'keys', 'institution_jwks.json');
const RUTA_RELATIVA_PRIVADA = '../infra/keys/institution_private.jwk.json';

const forzar = process.argv.includes('--force');
const CURVA = { name: 'ECDSA', namedCurve: 'P-256' };

/** `inst-<año-mes>-<6 hex>`; corto para no engordar el QR y estable por rotación. */
function nuevoKid() {
  const ahora = new Date();
  const mes = String(ahora.getUTCMonth() + 1).padStart(2, '0');
  return `inst-${ahora.getUTCFullYear()}-${mes}-${randomBytes(3).toString('hex')}`;
}

async function generarPar(kid) {
  const par = await crypto.subtle.generateKey(CURVA, true, ['sign', 'verify']);
  const privada = await crypto.subtle.exportKey('jwk', par.privateKey);
  const publica = await crypto.subtle.exportKey('jwk', par.publicKey);
  return {
    privada: { ...privada, kid, alg: 'ES256', use: 'sig' },
    publica: { ...publica, kid, alg: 'ES256', use: 'sig' },
  };
}

/** Añade o actualiza la clave pública del JWKS conservando las anteriores (rotación). */
function publicarEnJwks(publica) {
  mkdirSync(path.dirname(RUTA_PUBLICA), { recursive: true });
  let jwks = { keys: [] };
  if (existsSync(RUTA_PUBLICA)) {
    jwks = JSON.parse(readFileSync(RUTA_PUBLICA, 'utf8'));
    if (!Array.isArray(jwks.keys)) jwks.keys = [];
  }
  jwks.keys = jwks.keys.filter((clave) => clave.kid !== publica.kid);
  jwks.keys.push(publica);
  writeFileSync(RUTA_PUBLICA, `${JSON.stringify(jwks, null, 2)}\n`, 'utf8');
}

function imprimirInstrucciones(kid) {
  console.log('\nClaves institucionales listas:');
  console.log(`  privada : ${RUTA_PRIVADA}`);
  console.log(`  pública : ${RUTA_PUBLICA}`);
  console.log('\nAñade esto a api/.env (o al panel de Render):');
  console.log(`  INSTITUTION_KID=${kid}`);
  console.log(`  INSTITUTION_PRIVATE_KEY_PATH=${RUTA_RELATIVA_PRIVADA}`);
  console.log('\nEn Render (sin sistema de archivos) usa INSTITUTION_PRIVATE_KEY con el JWK en una línea.');
}

if (existsSync(RUTA_PRIVADA) && !forzar) {
  const existente = JSON.parse(readFileSync(RUTA_PRIVADA, 'utf8'));
  publicarEnJwks(existente.publica);
  console.log(`Ya existe el par institucional (kid ${existente.publica.kid}); usa --force para rotar.`);
  imprimirInstrucciones(existente.publica.kid);
  process.exit(0);
}

mkdirSync(DIRECTORIO_CLAVES, { recursive: true });
const kid = nuevoKid();
const { privada, publica } = await generarPar(kid);
writeFileSync(RUTA_PRIVADA, `${JSON.stringify({ kid, privada, publica }, null, 2)}\n`, 'utf8');
publicarEnJwks(publica);
imprimirInstrucciones(kid);
