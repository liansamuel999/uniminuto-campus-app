import 'dotenv/config';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import type { PoolClient } from 'pg';

import { cargarEnv } from '../../src/config/env.js';
import { crearPool } from '../../src/db/pool.js';
import {
  ASIGNATURAS,
  CLAVE_DEMO,
  HORARIOS,
  USUARIOS,
  asegurarUsuarioFirebase,
  cuentaDeServicio,
  enTransaccion,
  log,
} from './datos.js';

/**
 * Semilla idempotente de la Fase 1 (§7.6, D-54): usuarios + roles, programa, periodo, asignaturas,
 * grupos, inscripciones y estructura del campus Calle 80. Se puede ejecutar varias veces.
 *
 * Uso: npm run db:seed
 */

const env = cargarEnv();
const pool = crearPool(env.DATABASE_URL);

const cuenta = cuentaDeServicio(env);
if (cuenta) {
  if (getApps().length === 0) {
    const credenciales = JSON.parse(cuenta) as {
      project_id: string;
      client_email: string;
      private_key: string;
    };
    initializeApp({
      credential: cert({
        projectId: credenciales.project_id,
        clientEmail: credenciales.client_email,
        privateKey: credenciales.private_key,
      }),
    });
  }
} else {
  console.warn('⚠ Sin FIREBASE_SERVICE_ACCOUNT_PATH: se siembra solo la base con uids locales.');
}

const uidLocal = (codigo: string) => `demo-local-${codigo}`;

/** Fila del catálogo de usuarios ya resuelta con su uid de Firebase. */
interface UsuarioSembrado {
  id: string;
  correo: string;
  rol: string;
  docente: boolean;
}

async function upsertPrograma(cliente: PoolClient, nombre: string): Promise<string> {
  const resultado = await cliente.query<{ id: string }>(
    `INSERT INTO programa (nombre) VALUES ($1)
     ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
     RETURNING id`,
    [nombre],
  );
  return resultado.rows[0]!.id;
}

async function upsertPeriodo(cliente: PoolClient, codigo: string): Promise<string> {
  await cliente.query('UPDATE periodo SET activo = false WHERE codigo <> $1 AND activo', [codigo]);
  const resultado = await cliente.query<{ id: string }>(
    `INSERT INTO periodo (codigo, tipo, fecha_inicio, fecha_fin, activo)
     VALUES ($1, 'SEMESTRAL', '2026-08-03', '2026-11-27', true)
     ON CONFLICT (codigo) DO UPDATE SET activo = true
     RETURNING id`,
    [codigo],
  );
  return resultado.rows[0]!.id;
}

async function upsertUsuario(
  cliente: PoolClient,
  usuario: (typeof USUARIOS)[number],
  uidFirebase: string,
  programaId: string,
): Promise<string> {
  const resultado = await cliente.query<{ id: string }>(
    `INSERT INTO usuario (uid_firebase, nombres, apellidos, correo, documento, codigo_institucional, programa_id, estado)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'ACTIVO')
     ON CONFLICT (correo) DO UPDATE SET
       uid_firebase = EXCLUDED.uid_firebase,
       nombres = EXCLUDED.nombres,
       apellidos = EXCLUDED.apellidos,
       documento = EXCLUDED.documento,
       codigo_institucional = EXCLUDED.codigo_institucional,
       programa_id = EXCLUDED.programa_id,
       actualizado_en = now()
     RETURNING id`,
    [
      uidFirebase,
      usuario.nombres,
      usuario.apellidos,
      usuario.correo,
      usuario.documento,
      usuario.codigo,
      usuario.docente ? null : programaId,
    ],
  );
  const usuarioId = resultado.rows[0]!.id;

  await cliente.query(
    `INSERT INTO usuario_rol (usuario_id, rol_id)
     SELECT $1, r.id FROM rol r WHERE r.nombre = $2
     ON CONFLICT DO NOTHING`,
    [usuarioId, usuario.rol],
  );

  return usuarioId;
}

/** Crea (o actualiza) edificios, pisos y salones según §4.3. */
async function sembrarCampus(cliente: PoolClient): Promise<void> {
  const edificios: Array<{
    codigo: string;
    nombre: string;
    pisosEstudiantiles: number;
    pisosAdministrativos: number;
    laboratorios: string[];
  }> = [
    { codigo: 'A', nombre: 'Edificio A', pisosEstudiantiles: 4, pisosAdministrativos: 1, laboratorios: ['A-106', 'A-204'] },
    { codigo: 'B', nombre: 'Edificio B', pisosEstudiantiles: 5, pisosAdministrativos: 3, laboratorios: ['B-103', 'B-305'] },
    { codigo: 'C', nombre: 'Edificio C', pisosEstudiantiles: 5, pisosAdministrativos: 3, laboratorios: ['C-104', 'C-402'] },
  ];

  for (const edificio of edificios) {
    const filaEdificio = await cliente.query<{ id: string }>(
      `INSERT INTO edificio (codigo, nombre, sede) VALUES ($1, $2, 'CALLE_80')
       ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre
       RETURNING id`,
      [edificio.codigo, edificio.nombre],
    );
    const edificioId = filaEdificio.rows[0]!.id;

    const totalPisos = edificio.pisosEstudiantiles + edificio.pisosAdministrativos;
    for (let numero = 1; numero <= totalPisos; numero += 1) {
      const esAdministrativo = numero > edificio.pisosEstudiantiles;
      const filaPiso = await cliente.query<{ id: string }>(
        `INSERT INTO piso (edificio_id, numero, tipo) VALUES ($1, $2, $3)
         ON CONFLICT (edificio_id, numero) DO UPDATE SET tipo = EXCLUDED.tipo
         RETURNING id`,
        [edificioId, numero, esAdministrativo ? 'ADMINISTRATIVO' : 'ESTUDIANTIL'],
      );
      const pisoId = filaPiso.rows[0]!.id;

      const cantidad = esAdministrativo ? 5 : 10;
      const codigosGenerados: string[] = [];
      for (let indice = 1; indice <= cantidad; indice += 1) {
        const codigo = `${edificio.codigo}-${numero}${String(indice).padStart(2, '0')}`;
        codigosGenerados.push(codigo);
        const tipo = esAdministrativo
          ? 'OFICINA'
          : edificio.laboratorios.includes(codigo)
            ? 'LABORATORIO'
            : 'AULA';
        const capacidad = tipo === 'OFICINA' ? 4 : tipo === 'LABORATORIO' ? 25 : 35;

        await cliente.query(
          `INSERT INTO salon (piso_id, codigo, tipo, capacidad) VALUES ($1, $2, $3, $4)
           ON CONFLICT (codigo) DO UPDATE SET piso_id = EXCLUDED.piso_id, tipo = EXCLUDED.tipo, capacidad = EXCLUDED.capacidad`,
          [pisoId, codigo, tipo, capacidad],
        );
      }

      // §4.3: entre 3 y 5 oficinas por piso administrativo. Si una ejecución anterior dejó
      // oficinas de más, se eliminan para que la semilla converja al mismo estado.
      if (esAdministrativo) {
        await cliente.query(
          `DELETE FROM salon
           WHERE piso_id = $1 AND tipo = 'OFICINA' AND codigo <> ALL($2::text[])`,
          [pisoId, codigosGenerados],
        );
      }
    }
  }
}

async function principal(): Promise<void> {
  log(`Sembrando datos contra ${new URL(env.DATABASE_URL).host}`);

  const usuariosSembrados: UsuarioSembrado[] = [];

  await enTransaccion(pool, async (cliente) => {
    log('Programa y periodo');
    const programaId = await upsertPrograma(cliente, 'Ingeniería de Sistemas');
    const periodoId = await upsertPeriodo(cliente, '2026-2');

    log('Campus Calle 80 (edificios, pisos y salones)');
    await sembrarCampus(cliente);

    log('Usuarios, roles y claims');
    for (const usuario of USUARIOS) {
      const uid = cuenta
        ? await asegurarUsuarioFirebase(usuario.correo, usuario.nombres, usuario.apellidos, [usuario.rol])
        : uidLocal(usuario.codigo);
      const id = await upsertUsuario(cliente, usuario, uid, programaId);
      usuariosSembrados.push({
        id,
        correo: usuario.correo,
        rol: usuario.rol,
        docente: usuario.docente === true,
      });
    }

    const idPorCorreo = new Map(usuariosSembrados.map((usuario) => [usuario.correo, usuario.id]));

    log('Asignaturas, grupos, inscripciones y horarios');
    for (const asignatura of ASIGNATURAS) {
      const filaAsignatura = await cliente.query<{ id: string }>(
        `INSERT INTO asignatura (codigo, nombre, creditos) VALUES ($1, $2, $3)
         ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre, creditos = EXCLUDED.creditos
         RETURNING id`,
        [asignatura.codigo, asignatura.nombre, asignatura.creditos],
      );
      const asignaturaId = filaAsignatura.rows[0]!.id;

      const filaGrupo = await cliente.query<{ id: string }>(
        `INSERT INTO grupo (asignatura_id, periodo_id, docente_id, numero_grupo)
         VALUES ($1, $2, $3, '01')
         ON CONFLICT (asignatura_id, periodo_id, numero_grupo) DO UPDATE SET docente_id = EXCLUDED.docente_id
         RETURNING id`,
        [asignaturaId, periodoId, idPorCorreo.get(asignatura.docente) ?? null],
      );
      const grupoId = filaGrupo.rows[0]!.id;

      for (const estudiante of usuariosSembrados.filter((usuario) => usuario.rol === 'ESTUDIANTE')) {
        await cliente.query(
          `INSERT INTO inscripcion (estudiante_id, grupo_id, estado) VALUES ($1, $2, 'ACTIVA')
           ON CONFLICT (estudiante_id, grupo_id) DO UPDATE SET estado = 'ACTIVA'`,
          [estudiante.id, grupoId],
        );
      }

      for (const [dia, inicio, fin, salonCodigo] of HORARIOS[asignatura.codigo] ?? []) {
        const salon = await cliente.query<{ id: string }>('SELECT id FROM salon WHERE codigo = $1', [salonCodigo]);
        if (!salon.rows[0]) {
          throw new Error(`El salón ${salonCodigo} no existe; revisa la semilla del campus`);
        }
        await cliente.query(
          `INSERT INTO horario (grupo_id, salon_id, dia_semana, hora_inicio, hora_fin)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (grupo_id, dia_semana, hora_inicio) DO UPDATE SET salon_id = EXCLUDED.salon_id, hora_fin = EXCLUDED.hora_fin`,
          [grupoId, salon.rows[0].id, dia, inicio, fin],
        );
      }
    }
  });

  const resumen = await pool.query<{ usuarios: number; grupos: number; salones: number; horarios: number }>(
    `SELECT
       (SELECT count(*)::int FROM usuario) AS usuarios,
       (SELECT count(*)::int FROM grupo) AS grupos,
       (SELECT count(*)::int FROM salon) AS salones,
       (SELECT count(*)::int FROM horario) AS horarios`,
  );

  const fila = resumen.rows[0]!;
  console.log('\nSemilla aplicada correctamente:');
  console.log(`  usuarios : ${fila.usuarios}`);
  console.log(`  grupos   : ${fila.grupos}`);
  console.log(`  salones  : ${fila.salones}`);
  console.log(`  horarios : ${fila.horarios}`);
  console.log(`\nCredenciales de demostración: <correo> / ${CLAVE_DEMO} (dominio @${'demo.uniminuto.test'})`);

  await pool.end();
}

principal().catch(async (error) => {
  console.error('La semilla falló:', error instanceof Error ? error.message : error);
  await pool.end().catch(() => undefined);
  process.exit(1);
});
