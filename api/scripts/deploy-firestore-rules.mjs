#!/usr/bin/env node
/**
 * Despliega `infra/firebase/firestore.rules` con la cuenta de servicio de Firebase (D-65).
 *
 * Sustituye a `firebase deploy --only firestore:rules` cuando la CLI de Firebase no está
 * instalada o no hay sesión interactiva: usa las mismas credenciales que la API y la API REST
 * de Firebase Rules, así que sirve igual en local y en un host sin navegador.
 *
 * Uso: `npm run rules:deploy` desde `api/` (o `npm --prefix api run rules:deploy`).
 */
import 'dotenv/config';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cert, initializeApp } from 'firebase-admin/app';

const RAIZ_API = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REGLAS = path.resolve(RAIZ_API, '../infra/firebase/firestore.rules');

function resolverRuta(ruta) {
  return path.isAbsolute(ruta) ? ruta : path.resolve(RAIZ_API, ruta);
}

const rutaCuenta = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
if (!rutaCuenta) {
  console.error('Falta FIREBASE_SERVICE_ACCOUNT_PATH en api/.env');
  process.exit(1);
}

const cuenta = JSON.parse(readFileSync(resolverRuta(rutaCuenta), 'utf8'));
const proyecto = cuenta.project_id;
const app = initializeApp({
  credential: cert({
    projectId: cuenta.project_id,
    clientEmail: cuenta.client_email,
    privateKey: cuenta.private_key,
  }),
});

const { access_token: token } = await app.options.credential.getAccessToken();
const comun = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const contenido = readFileSync(REGLAS, 'utf8');

async function llamar(metodo, url, cuerpo) {
  const respuesta = await fetch(url, {
    method: metodo,
    headers: comun,
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    console.error(`${metodo} ${url} -> ${respuesta.status}`);
    console.error(texto);
    process.exit(1);
  }
  return texto ? JSON.parse(texto) : {};
}

console.log(`Proyecto: ${proyecto}`);
console.log(`Reglas:   ${path.relative(RAIZ_API, REGLAS)}`);

const ruleset = await llamar(
  'POST',
  `https://firebaserules.googleapis.com/v1/projects/${proyecto}/rulesets`,
  { source: { files: [{ name: 'firestore.rules', content: contenido }] } },
);
console.log(`Ruleset creado: ${ruleset.name}`);

await llamar(
  'PATCH',
  `https://firebaserules.googleapis.com/v1/projects/${proyecto}/releases/cloud.firestore`,
  {
    release: {
      name: `projects/${proyecto}/releases/cloud.firestore`,
      rulesetName: ruleset.name,
    },
    updateMask: 'rulesetName',
  },
);

console.log('Reglas de Firestore desplegadas y activas en el release cloud.firestore.');
