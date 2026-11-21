import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Pool, PoolClient } from 'pg';
import { getAuth } from 'firebase-admin/auth';

import { leerCuentaDeServicioFirebase } from '../../src/config/firebase_credentials.js';
import type { Env } from '../../src/config/env.js';
import { crearPool } from '../../src/db/pool.js';

export { crearPool };
export type { Env };

/** Programa académico de la muestra. */
export interface ProgramaSemilla {
  readonly nombre: string;
}

export const PROGRAMAS: readonly ProgramaSemilla[] = [
  { nombre: 'Ingeniería de Sistemas' },
  { nombre: 'Administración de Empresas' },
  { nombre: 'Psicología' },
];

/** Catálogo de usuarios ficticios de la demostración. */
export interface UsuarioSemilla {
  readonly correo: string;
  readonly nombres: string;
  readonly apellidos: string;
  readonly codigo: string;
  readonly documento: string;
  readonly rol: string;
  readonly docente?: boolean;
  /** Turnos en los que puede dictar clase: MANANA, TARDE, NOCHE. */
  readonly turnos?: readonly string[];
  /** Programa al que pertenece el estudiante (los docentes y administrativos no tienen). */
  readonly programa?: string;
}

export const CLAVE_DEMO = 'Demo1234*';
export const DOMINIO_DEMO = 'demo.uniminuto.test';

const ESTUDIANTES = (filas: Array<[string, string, string, string, string]>): UsuarioSemilla[] =>
  filas.map(([correo, nombres, apellidos, codigo, programa]) => ({
    correo: `${correo}@${DOMINIO_DEMO}`,
    nombres,
    apellidos,
    codigo,
    documento: `10${codigo.slice(-6)}`,
    rol: 'ESTUDIANTE',
    programa,
  }));

export const USUARIOS: readonly UsuarioSemilla[] = [
  // Docentes
  { correo: 'carolina.pena@demo.uniminuto.test', nombres: 'Carolina', apellidos: 'Peña Salgado', codigo: 'DOC-201', documento: '2002002001', rol: 'DOCENTE', docente: true, turnos: ['MANANA', 'TARDE'] },
  { correo: 'diego.suarez@demo.uniminuto.test', nombres: 'Diego Armando', apellidos: 'Suárez Ortiz', codigo: 'DOC-202', documento: '2002002002', rol: 'DOCENTE', docente: true, turnos: ['TARDE', 'NOCHE'] },
  { correo: 'andrea.rincon@demo.uniminuto.test', nombres: 'Andrea', apellidos: 'Rincón Molina', codigo: 'DOC-203', documento: '2002002003', rol: 'DOCENTE', docente: true, turnos: ['MANANA'] },
  { correo: 'julian.pardo@demo.uniminuto.test', nombres: 'Julián', apellidos: 'Pardo Benítez', codigo: 'DOC-204', documento: '2002002004', rol: 'DOCENTE', docente: true, turnos: ['MANANA', 'TARDE'] },
  { correo: 'paula.restrepo@demo.uniminuto.test', nombres: 'Paula', apellidos: 'Restrepo Lozano', codigo: 'DOC-205', documento: '2002002005', rol: 'DOCENTE', docente: true, turnos: ['TARDE', 'NOCHE'] },
  { correo: 'sofia.herrera@demo.uniminuto.test', nombres: 'Sofía', apellidos: 'Herrera Pineda', codigo: 'DOC-206', documento: '2002002006', rol: 'DOCENTE', docente: true, turnos: ['NOCHE'] },

  // Administrativos y apoyo
  { correo: 'luisa.castro@demo.uniminuto.test', nombres: 'Luisa Fernanda', apellidos: 'Castro Ríos', codigo: 'ADM-301', documento: '3003003001', rol: 'ADMIN_ACADEMICO' },
  { correo: 'camilo.vega@demo.uniminuto.test', nombres: 'Camilo Andrés', apellidos: 'Vega Torres', codigo: 'ADM-302', documento: '3003003002', rol: 'ADMIN_ACADEMICO' },
  { correo: 'jorge.salazar@demo.uniminuto.test', nombres: 'Jorge Enrique', apellidos: 'Salazar Bravo', codigo: 'SEG-401', documento: '4004004001', rol: 'SEGURIDAD' },
  { correo: 'natalia.gomez@demo.uniminuto.test', nombres: 'Natalia', apellidos: 'Gómez Pardo', codigo: 'SOP-501', documento: '5005005001', rol: 'SOPORTE' },
  { correo: 'oscar.rincon@demo.uniminuto.test', nombres: 'Óscar Iván', apellidos: 'Rincón Duarte', codigo: 'AUD-601', documento: '6006006001', rol: 'AUDITOR' },

  // Estudiantes de Ingeniería de Sistemas
  ...ESTUDIANTES([
    ['juan.rojas', 'Juan Pablo', 'Rojas Méndez', '20261001', 'Ingeniería de Sistemas'],
    ['maria.cardenas', 'María Fernanda', 'Cárdenas López', '20261002', 'Ingeniería de Sistemas'],
    ['andres.molina', 'Andrés Felipe', 'Molina Ariza', '20261003', 'Ingeniería de Sistemas'],
    ['camila.ortiz', 'Camila Andrea', 'Ortiz Villalba', '20261004', 'Ingeniería de Sistemas'],
    ['santiago.moreno', 'Santiago', 'Moreno Cely', '20261005', 'Ingeniería de Sistemas'],
    ['valentina.ramirez', 'Valentina', 'Ramírez Cuervo', '20261006', 'Ingeniería de Sistemas'],
    ['felipe.castillo', 'Felipe', 'Castillo Rojas', '20261007', 'Ingeniería de Sistemas'],
    ['laura.jimenez', 'Laura Sofía', 'Jiménez Medina', '20261008', 'Ingeniería de Sistemas'],
  ]),

  // Estudiantes de Administración de Empresas
  ...ESTUDIANTES([
    ['paula.mendoza', 'Paula Andrea', 'Mendoza Quintero', '20262001', 'Administración de Empresas'],
    ['mateo.herrera', 'Mateo', 'Herrera Sánchez', '20262002', 'Administración de Empresas'],
    ['daniela.suarez', 'Daniela', 'Suárez Peña', '20262003', 'Administración de Empresas'],
    ['sebastian.pardo', 'Sebastián', 'Pardo Ramírez', '20262004', 'Administración de Empresas'],
  ]),

  // Estudiantes de Psicología
  ...ESTUDIANTES([
    ['isabella.gomez', 'Isabella', 'Gómez Salazar', '20263001', 'Psicología'],
    ['sara.navarro', 'Sara', 'Navarro Cifuentes', '20263002', 'Psicología'],
    ['tomas.quintero', 'Tomás', 'Quintero Mora', '20263003', 'Psicología'],
  ]),
];

/** Curso (oferta) con su propio código, docente, estudiantes y horario. */
export interface CursoSemilla {
  readonly asignatura: string;
  readonly nombre: string;
  readonly creditos: number;
  readonly requiereLaboratorio: boolean;
  /** Código único del curso (NRC): identifica la oferta. */
  readonly codigoCurso: string;
  /** Número interno para la restricción histórica (asignatura, periodo, número). */
  readonly numero: string;
  readonly docente: string;
  readonly estudiantes: readonly string[];
  /** [día ISO, inicio, fin, salón]. */
  readonly horarios: ReadonlyArray<readonly [number, string, string, string]>;
}

const est = (...correos: string[]): string[] => correos.map((correo) => `${correo}@${DOMINIO_DEMO}`);

export const CURSOS: readonly CursoSemilla[] = [
  // Ingeniería de Sistemas
  {
    asignatura: 'IS-101', nombre: 'Programación I', creditos: 4, requiereLaboratorio: false,
    codigoCurso: '1234', numero: '01', docente: 'carolina.pena@demo.uniminuto.test',
    estudiantes: est('juan.rojas', 'maria.cardenas', 'andres.molina', 'camila.ortiz', 'santiago.moreno', 'valentina.ramirez'),
    horarios: [[1, '07:00', '09:00', 'A-301'], [3, '07:00', '09:00', 'A-301']],
  },
  {
    asignatura: 'IS-201', nombre: 'Bases de Datos', creditos: 3, requiereLaboratorio: true,
    codigoCurso: '1235', numero: '01', docente: 'carolina.pena@demo.uniminuto.test',
    estudiantes: est('juan.rojas', 'maria.cardenas', 'andres.molina', 'camila.ortiz', 'santiago.moreno'),
    horarios: [[2, '09:00', '11:00', 'A-106'], [4, '09:00', '11:00', 'A-106']],
  },
  {
    asignatura: 'IS-201', nombre: 'Bases de Datos', creditos: 3, requiereLaboratorio: true,
    codigoCurso: '2235', numero: '02', docente: 'carolina.pena@demo.uniminuto.test',
    estudiantes: est('valentina.ramirez', 'felipe.castillo', 'laura.jimenez'),
    horarios: [[2, '11:00', '13:00', 'A-204'], [4, '11:00', '13:00', 'A-204']],
  },
  {
    asignatura: 'IS-301', nombre: 'Redes de Computadores', creditos: 3, requiereLaboratorio: true,
    codigoCurso: '1236', numero: '01', docente: 'diego.suarez@demo.uniminuto.test',
    estudiantes: est('juan.rojas', 'andres.molina', 'felipe.castillo'),
    horarios: [[1, '11:00', '13:00', 'C-104'], [5, '11:00', '13:00', 'C-104']],
  },
  {
    asignatura: 'IS-301', nombre: 'Redes de Computadores', creditos: 3, requiereLaboratorio: true,
    codigoCurso: '2236', numero: '02', docente: 'diego.suarez@demo.uniminuto.test',
    estudiantes: est('santiago.moreno', 'laura.jimenez'),
    horarios: [[3, '14:00', '16:00', 'C-402'], [5, '14:00', '16:00', 'C-402']],
  },
  {
    asignatura: 'IS-401', nombre: 'Ingeniería de Software', creditos: 4, requiereLaboratorio: false,
    codigoCurso: '1237', numero: '01', docente: 'diego.suarez@demo.uniminuto.test',
    estudiantes: est('maria.cardenas', 'camila.ortiz', 'valentina.ramirez', 'laura.jimenez'),
    horarios: [[2, '14:00', '16:00', 'A-205'], [4, '14:00', '16:00', 'A-205']],
  },
  {
    // Curso sin horario: el admin académico le asigna salón con el planificador.
    asignatura: 'IS-401', nombre: 'Ingeniería de Software', creditos: 4, requiereLaboratorio: false,
    codigoCurso: '2237', numero: '02', docente: 'diego.suarez@demo.uniminuto.test',
    estudiantes: est('santiago.moreno', 'felipe.castillo'),
    horarios: [],
  },
  {
    asignatura: 'IS-501', nombre: 'Inteligencia Artificial', creditos: 3, requiereLaboratorio: true,
    codigoCurso: '1238', numero: '01', docente: 'andrea.rincon@demo.uniminuto.test',
    estudiantes: est('juan.rojas', 'maria.cardenas', 'santiago.moreno', 'felipe.castillo'),
    horarios: [[3, '16:00', '18:00', 'A-302'], [5, '16:00', '18:00', 'A-302']],
  },
  {
    asignatura: 'MAT-101', nombre: 'Cálculo Diferencial', creditos: 4, requiereLaboratorio: false,
    codigoCurso: '1239', numero: '01', docente: 'julian.pardo@demo.uniminuto.test',
    estudiantes: est('juan.rojas', 'maria.cardenas', 'andres.molina', 'camila.ortiz', 'santiago.moreno', 'valentina.ramirez', 'felipe.castillo', 'laura.jimenez'),
    horarios: [[1, '09:00', '11:00', 'A-303'], [3, '09:00', '11:00', 'A-303']],
  },

  // Administración de Empresas
  {
    asignatura: 'ADM-101', nombre: 'Fundamentos de Administración', creditos: 3, requiereLaboratorio: false,
    codigoCurso: '1240', numero: '01', docente: 'paula.restrepo@demo.uniminuto.test',
    estudiantes: est('paula.mendoza', 'mateo.herrera', 'daniela.suarez', 'sebastian.pardo'),
    horarios: [[2, '07:00', '09:00', 'A-304'], [4, '07:00', '09:00', 'A-304']],
  },
  {
    asignatura: 'ADM-201', nombre: 'Contabilidad General', creditos: 3, requiereLaboratorio: false,
    codigoCurso: '1241', numero: '01', docente: 'paula.restrepo@demo.uniminuto.test',
    estudiantes: est('paula.mendoza', 'mateo.herrera', 'daniela.suarez', 'sebastian.pardo'),
    horarios: [[2, '09:00', '11:00', 'A-305'], [4, '09:00', '11:00', 'A-305']],
  },
  {
    asignatura: 'ADM-301', nombre: 'Estadística', creditos: 3, requiereLaboratorio: false,
    codigoCurso: '1242', numero: '01', docente: 'julian.pardo@demo.uniminuto.test',
    estudiantes: est('paula.mendoza', 'mateo.herrera', 'daniela.suarez', 'sebastian.pardo', 'isabella.gomez', 'sara.navarro'),
    horarios: [[3, '11:00', '13:00', 'A-306'], [5, '11:00', '13:00', 'A-306']],
  },

  // Psicología
  {
    asignatura: 'PSI-101', nombre: 'Psicología General', creditos: 3, requiereLaboratorio: false,
    codigoCurso: '1243', numero: '01', docente: 'sofia.herrera@demo.uniminuto.test',
    estudiantes: est('isabella.gomez', 'sara.navarro', 'tomas.quintero'),
    horarios: [[2, '14:00', '16:00', 'A-307'], [4, '14:00', '16:00', 'A-307']],
  },
  {
    asignatura: 'PSI-201', nombre: 'Psicología del Desarrollo', creditos: 3, requiereLaboratorio: false,
    codigoCurso: '1244', numero: '01', docente: 'paula.restrepo@demo.uniminuto.test',
    estudiantes: est('isabella.gomez', 'sara.navarro', 'tomas.quintero'),
    horarios: [[3, '07:00', '09:00', 'A-308'], [5, '07:00', '09:00', 'A-308']],
  },
  {
    asignatura: 'PSI-301', nombre: 'Neuropsicología', creditos: 3, requiereLaboratorio: false,
    codigoCurso: '1245', numero: '01', docente: 'sofia.herrera@demo.uniminuto.test',
    estudiantes: est('sara.navarro', 'tomas.quintero'),
    horarios: [[3, '09:00', '11:00', 'A-309'], [5, '09:00', '11:00', 'A-309']],
  },
];

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
