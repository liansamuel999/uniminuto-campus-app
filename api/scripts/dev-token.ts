import 'dotenv/config';
import { cargarEnv } from '../src/config/env.js';
import { firmarTokenDev } from '../src/modules/auth/verifier.js';

/**
 * Imprime un token HS256 de desarrollo para probar la API sin Firebase (D-20).
 * Uso: npm run token:dev [uid] [ROL1,ROL2]
 */
const env = cargarEnv();

if (!env.AUTH_DEV_SECRET) {
  console.error('AUTH_DEV_SECRET no está configurado en api/.env; no se puede firmar un token de prueba.');
  process.exit(1);
}

const uid = process.argv[2] ?? 'uid-demo-estudiante';
const roles = (process.argv[3] ?? 'ESTUDIANTE')
  .split(',')
  .map((rol) => rol.trim())
  .filter((rol) => rol.length > 0);

const token = await firmarTokenDev({
  uid,
  secreto: env.AUTH_DEV_SECRET,
  roles,
  correo: `${uid}@demo.uniminuto.test`,
});

console.log(token);
