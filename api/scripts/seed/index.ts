import 'dotenv/config';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
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
  uid: string;
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

  // Carnet digital (§4.2): uno por usuario, código Code 128 y vigencia de un año.
  const codigoBarras = `UNI-${usuario.codigo}`;
  await cliente.query(
    `INSERT INTO carnet (usuario_id, codigo_barras, estado, vigente_hasta)
     VALUES ($1, $2, 'ACTIVO', (now() + interval '1 year')::date)
     ON CONFLICT (codigo_barras) DO UPDATE SET usuario_id = EXCLUDED.usuario_id`,
    [usuarioId, codigoBarras],
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

/** Cabinas y salas de autorecreación solicitadas por el cliente (Fase 3). */
async function sembrarEspaciosReservables(cliente: PoolClient): Promise<void> {
  const espacios: Array<readonly [string, 'INDIVIDUAL' | 'GRUPO', number]> = [
    ['Cabina 1', 'INDIVIDUAL', 1],
    ['Cabina 2', 'INDIVIDUAL', 1],
    ['Cabina 3', 'INDIVIDUAL', 1],
    ['Cabina 4', 'INDIVIDUAL', 1],
    ['Cabina 5', 'INDIVIDUAL', 1],
    ['Cabina 6', 'INDIVIDUAL', 1],
    ['Sala A (4 personas)', 'GRUPO', 4],
    ['Sala B (4 personas)', 'GRUPO', 4],
    ['Sala C (4 personas)', 'GRUPO', 4],
    ['Sala D (5 personas)', 'GRUPO', 5],
    ['Sala E (6 personas)', 'GRUPO', 6],
  ];

  for (const [nombre, tipo, capacidad] of espacios) {
    await cliente.query(
      `INSERT INTO espacio_reservable (nombre, tipo, capacidad, activo) VALUES ($1, $2, $3, true)
       ON CONFLICT (nombre) DO UPDATE SET tipo = EXCLUDED.tipo, capacidad = EXCLUDED.capacidad, activo = true`,
      [nombre, tipo, capacidad],
    );
  }
}

/** Aula virtual con 3 cortes, 2 unidades, contenidos, actividades y una nota de ejemplo. */
async function sembrarAulaVirtual(
  cliente: PoolClient,
  datos: { grupoId: string; nombre: string; docenteUid?: string; estudiantes: UsuarioSembrado[] },
): Promise<void> {
  const cortes: Record<number, string> = {};
  for (const [numero, peso] of [[1, 30], [2, 30], [3, 40]] as const) {
    const fila = await cliente.query<{ id: string }>(
      `INSERT INTO corte (grupo_id, numero, peso_porcentual) VALUES ($1, $2, $3)
       ON CONFLICT (grupo_id, numero) DO UPDATE SET peso_porcentual = EXCLUDED.peso_porcentual
       RETURNING id`,
      [datos.grupoId, numero, peso],
    );
    cortes[numero] = fila.rows[0]!.id;
  }

  const aula = await cliente.query<{ id: string }>(
    `INSERT INTO aula (grupo_id, nombre, descripcion) VALUES ($1, $2, 'Aula virtual de la asignatura')
     ON CONFLICT (grupo_id) DO UPDATE SET nombre = EXCLUDED.nombre
     RETURNING id`,
    [datos.grupoId, datos.nombre],
  );
  const aulaId = aula.rows[0]!.id;

  // Espejo para las reglas de Firestore: solo la API (Admin SDK) escribe aulas_index.
  if (getApps().length > 0) {
    await getFirestore()
      .doc(`aulas_index/${aulaId}`)
      .set({
        miembros: datos.estudiantes.map((estudiante) => estudiante.uid),
        docentes: datos.docenteUid ? [datos.docenteUid] : [],
      }, { merge: true });
  }

  const unidades = [
    { numero: 1, titulo: 'Fundamentos y entorno de trabajo' },
    { numero: 2, titulo: 'Aplicación práctica y evaluación' },
  ] as const;

  for (const unidad of unidades) {
    const filaUnidad = await cliente.query<{ id: string }>(
      `INSERT INTO unidad (aula_id, numero, titulo) VALUES ($1, $2, $3)
       ON CONFLICT (aula_id, numero) DO UPDATE SET titulo = EXCLUDED.titulo
       RETURNING id`,
      [aulaId, unidad.numero, unidad.titulo],
    );
    const unidadId = filaUnidad.rows[0]!.id;

    const contenidos = unidad.numero === 1
      ? [
          { tipo: 'PDF', titulo: 'Guía de la unidad', objetoKey: 'aulas/demo/guia-unidad.pdf', mime: 'application/pdf' },
          { tipo: 'ENLACE', titulo: 'Documentación recomendada', url: 'https://developer.mozilla.org/es/' },
        ]
      : [
          { tipo: 'VIDEO', titulo: 'Video de la unidad', objetoKey: 'aulas/demo/video-unidad.mp4', mime: 'video/mp4' },
          { tipo: 'ANUNCIO', titulo: 'Recordatorio de entrega' },
        ];

    for (const contenido of contenidos) {
      const existe = await cliente.query(
        'SELECT 1 FROM contenido WHERE unidad_id = $1 AND titulo = $2',
        [unidadId, contenido.titulo],
      );
      if ((existe.rowCount ?? 0) > 0) continue;
      await cliente.query(
        `INSERT INTO contenido (unidad_id, tipo, titulo, objeto_key, url_externa, mime)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [unidadId, contenido.tipo, contenido.titulo, contenido.objetoKey ?? null, contenido.url ?? null, contenido.mime ?? null],
      );
    }

    const actividades = unidad.numero === 1
      ? [
          { tipo: 'TAREA', titulo: 'Taller de la unidad 1', peso: 50, corte: 1 },
          { tipo: 'CUESTIONARIO', titulo: 'Cuestionario de la unidad 1', peso: 50, corte: 1 },
        ]
      : [
          { tipo: 'FORO', titulo: 'Foro de discusión', peso: 40, corte: 2 },
        ];

    for (const actividad of actividades) {
      const existeActividad = await cliente.query(
        'SELECT 1 FROM actividad WHERE unidad_id = $1 AND titulo = $2',
        [unidadId, actividad.titulo],
      );
      if ((existeActividad.rowCount ?? 0) > 0) continue;

      const filaActividad = await cliente.query<{ id: string }>(
        `INSERT INTO actividad (unidad_id, tipo, titulo, instrucciones, cierra_en, corte_id, peso_porcentual)
         VALUES ($1, $2, $3, 'Actividad de demostración con datos ficticios', now() + interval '14 days', $4, $5)
         RETURNING id`,
        [unidadId, actividad.tipo, actividad.titulo, cortes[actividad.corte], actividad.peso],
      );
      const actividadId = filaActividad.rows[0]?.id;
      if (!actividadId) continue;

      if (actividad.tipo === 'CUESTIONARIO') {
        for (let orden = 1; orden <= 3; orden += 1) {
          const pregunta = await cliente.query<{ id: string }>(
            `INSERT INTO pregunta (actividad_id, enunciado, orden) VALUES ($1, $2, $3) RETURNING id`,
            [actividadId, `Pregunta ${orden} de la unidad 1`, orden],
          );
          const preguntaId = pregunta.rows[0]!.id;
          for (const [indice, texto] of ['Opción A', 'Opción B', 'Opción C'].entries()) {
            await cliente.query(
              `INSERT INTO opcion_respuesta (pregunta_id, texto, es_correcta, orden) VALUES ($1, $2, $3, $4)`,
              [preguntaId, texto, indice === 0, indice + 1],
            );
          }
        }
      }

      if (actividad.tipo === 'TAREA' && datos.estudiantes.length > 0) {
        const inscripcion = await cliente.query<{ id: string }>(
          'SELECT id FROM inscripcion WHERE estudiante_id = $1 AND grupo_id = $2',
          [datos.estudiantes[0]!.id, datos.grupoId],
        );
        const inscripcionId = inscripcion.rows[0]?.id;
        if (inscripcionId) {
          await cliente.query(
            `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
             VALUES ($1, $2, 4.2, 'Buen trabajo en la demostración')
             ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
            [actividadId, inscripcionId],
          );
        }
      }
    }
  }
}

async function principal(): Promise<void> {  log(`Sembrando datos contra ${new URL(env.DATABASE_URL).host}`);

  const usuariosSembrados: UsuarioSembrado[] = [];

  await enTransaccion(pool, async (cliente) => {
    log('Programa y periodo');
    const programaId = await upsertPrograma(cliente, 'Ingeniería de Sistemas');
    const periodoId = await upsertPeriodo(cliente, '2026-2');

    log('Campus Calle 80 (edificios, pisos y salones)');
    await sembrarCampus(cliente);

    log('Espacios de autorecreación (cabinas y salas)');
    await sembrarEspaciosReservables(cliente);

    log('Usuarios, roles y claims');
    for (const usuario of USUARIOS) {
      const uid = cuenta
        ? await asegurarUsuarioFirebase(usuario.correo, usuario.nombres, usuario.apellidos, [usuario.rol])
        : uidLocal(usuario.codigo);
      const id = await upsertUsuario(cliente, usuario, uid, programaId);
      usuariosSembrados.push({
        id,
        uid,
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

      await sembrarAulaVirtual(cliente, {
        grupoId,
        nombre: `${asignatura.nombre} · Grupo 01`,
        docenteUid: usuariosSembrados.find((usuario) => usuario.correo === asignatura.docente)?.uid,
        estudiantes: usuariosSembrados.filter((usuario) => usuario.rol === 'ESTUDIANTE'),
      });

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

    log('Incidencias de demostración');
    const estudianteDemo = usuariosSembrados.find((usuario) => usuario.rol === 'ESTUDIANTE');
    if (estudianteDemo) {
      const incidenciasDemo = [
        'El lector de la entrada del Edificio B no reconoce el QR del carnet',
        'La sala de autorecreación B-301 aparece ocupada sin reserva',
      ];
      for (const descripcion of incidenciasDemo) {
        const existe = await cliente.query('SELECT 1 FROM incidencia WHERE descripcion = $1', [
          descripcion,
        ]);
        if ((existe.rowCount ?? 0) === 0) {
          await cliente.query('INSERT INTO incidencia (usuario_id, descripcion) VALUES ($1, $2)', [
            estudianteDemo.id,
            descripcion,
          ]);
        }
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
  if (error instanceof Error && error.stack) console.error(error.stack);
  await pool.end().catch(() => undefined);
  process.exit(1);
});
