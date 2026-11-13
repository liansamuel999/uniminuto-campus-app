import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Pool, PoolClient } from 'pg';
import { getAuth } from 'firebase-admin/auth';

import { leerCuentaDeServicioFirebase } from '../../src/config/firebase_credentials.js';
import type { Env } from '../../src/config/env.js';
import { crearPool } from '../../src/db/pool.js';

export { crearPool };
export type { Env };

/** IDs y nombres del campus que exige §4.3 y §7.6. */
export interface UsuarioSemilla {
  readonly correo: string;
  readonly nombres: string;
  readonly apellidos: string;
  readonly codigo: string;
  readonly documento: string;
  readonly rol: string;
  readonly docente?: boolean;
}

export const CLAVE_DEMO = 'Demo1234*';
export const DOMINIO_DEMO = 'demo.uniminuto.test';

export const USUARIOS: readonly UsuarioSemilla[] = [
  { correo: 'juan.rojas@demo.uniminuto.test', nombres: 'Juan Pablo', apellidos: 'Rojas Méndez', codigo: '20261001', documento: '1001001001', rol: 'ESTUDIANTE' },
  { correo: 'maria.cardenas@demo.uniminuto.test', nombres: 'María Fernanda', apellidos: 'Cárdenas López', codigo: '20261002', documento: '1001001002', rol: 'ESTUDIANTE' },
  { correo: 'andres.molina@demo.uniminuto.test', nombres: 'Andrés Felipe', apellidos: 'Molina Ariza', codigo: '20261003', documento: '1001001003', rol: 'ESTUDIANTE' },
  { correo: 'carolina.pena@demo.uniminuto.test', nombres: 'Carolina', apellidos: 'Peña Salgado', codigo: 'DOC-201', documento: '2002002001', rol: 'DOCENTE', docente: true },
  { correo: 'diego.suarez@demo.uniminuto.test', nombres: 'Diego Armando', apellidos: 'Suárez Ortiz', codigo: 'DOC-202', documento: '2002002002', rol: 'DOCENTE', docente: true },
  { correo: 'luisa.castro@demo.uniminuto.test', nombres: 'Luisa Fernanda', apellidos: 'Castro Ríos', codigo: 'ADM-301', documento: '3003003001', rol: 'ADMIN_ACADEMICO' },
  { correo: 'camilo.vega@demo.uniminuto.test', nombres: 'Camilo Andrés', apellidos: 'Vega Torres', codigo: 'ADM-302', documento: '3003003002', rol: 'ADMIN_ESPACIOS' },
  { correo: 'jorge.salazar@demo.uniminuto.test', nombres: 'Jorge Enrique', apellidos: 'Salazar Bravo', codigo: 'SEG-401', documento: '4004004001', rol: 'SEGURIDAD' },
  { correo: 'natalia.gomez@demo.uniminuto.test', nombres: 'Natalia', apellidos: 'Gómez Pardo', codigo: 'SOP-501', documento: '5005005001', rol: 'SOPORTE' },
  { correo: 'oscar.rincon@demo.uniminuto.test', nombres: 'Óscar Iván', apellidos: 'Rincón Duarte', codigo: 'AUD-601', documento: '6006006001', rol: 'AUDITOR' },
];

export const ASIGNATURAS = [
  { codigo: 'IS-101', nombre: 'Programación I', creditos: 4, docente: 'carolina.pena@demo.uniminuto.test' },
  { codigo: 'IS-201', nombre: 'Bases de Datos', creditos: 3, docente: 'carolina.pena@demo.uniminuto.test' },
  { codigo: 'IS-301', nombre: 'Redes de Computadores', creditos: 3, docente: 'diego.suarez@demo.uniminuto.test' },
  { codigo: 'IS-401', nombre: 'Ingeniería de Software', creditos: 4, docente: 'diego.suarez@demo.uniminuto.test' },
] as const;

/** Horario semanal por asignatura: [día ISO, inicio, fin, salón]. */
export const HORARIOS: Record<string, ReadonlyArray<readonly [number, string, string, string]>> = {
  'IS-101': [[1, '07:00', '09:00', 'A-301'], [3, '07:00', '09:00', 'A-301']],
  'IS-201': [[2, '09:00', '11:00', 'B-204'], [4, '09:00', '11:00', 'B-204']],
  'IS-301': [[1, '11:00', '13:00', 'C-105'], [5, '11:00', '13:00', 'C-105']],
  'IS-401': [[2, '14:00', '16:00', 'A-205'], [4, '14:00', '16:00', 'A-205']],
};

/** Traduce `backend/src/...` a rutas relativas al paquete api. */
export const RAIZ_API = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export function rutaCredenciales(env: Env, rutaRelativa: string): string {
  return path.isAbsolute(rutaRelativa) ? rutaRelativa : path.resolve(RAIZ_API, rutaRelativa);
}

export function log(mensaje: string): void {
  console.log(`  ${mensaje}`);
}

export async function enTransaccion<T>(pool: Pool, trabajo: (cliente: PoolClient) => Promise<T>): Promise<T> {
  const cliente = await pool.connect();
  try {
    await cliente.query('BEGIN');
    const resultado = await trabajo(cliente);
    await cliente.query('COMMIT');
    return resultado;
  } catch (error) {
    await cliente.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    cliente.release();
  }
}

/** Crea (o recupera) el usuario de Firebase y fija sus claims `roles` (§5). */
export async function asegurarUsuarioFirebase(
  correo: string,
  nombres: string,
  apellidos: string,
  roles: string[],
): Promise<string> {
  const auth = getAuth();
  let uid: string;
  try {
    uid = (await auth.getUserByEmail(correo)).uid;
  } catch {
    const creado = await auth.createUser({
      email: correo,
      password: CLAVE_DEMO,
      displayName: `${nombres} ${apellidos}`,
      emailVerified: true,
    });
    uid = creado.uid;
  }
  await auth.setCustomUserClaims(uid, { roles });
  return uid;
}

/** JSON de la cuenta de servicio o `undefined` si no está configurada (modo solo base). */
export function cuentaDeServicio(env: Env): string | undefined {
  const cuenta = leerCuentaDeServicioFirebase(env);
  if (!cuenta) return undefined;
  return cuenta;
}
