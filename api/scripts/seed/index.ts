import { randomUUID } from 'node:crypto';
import 'dotenv/config';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { PoolClient } from 'pg';

import { cargarEnv } from '../../src/config/env.js';
import { crearPool } from '../../src/db/pool.js';
import {
  CLAVE_DEMO,
  CURSOS,
  PROGRAMAS,
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
  programaId: string | null,
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

  // Sincroniza los roles exactos del usuario (limpia roles obsoletos como ADMIN_ESPACIOS).
  await cliente.query(
    `DELETE FROM usuario_rol
     WHERE usuario_id = $1
       AND rol_id NOT IN (SELECT id FROM rol WHERE nombre = $2)`,
    [usuarioId, usuario.rol],
  );
  await cliente.query(
    `INSERT INTO usuario_rol (usuario_id, rol_id)
     SELECT $1, r.id FROM rol r WHERE r.nombre = $2
     ON CONFLICT DO NOTHING`,
    [usuarioId, usuario.rol],
  );

  if (usuario.docente) {
    await cliente.query(
      'UPDATE usuario SET turnos_disponibles = $2::text[] WHERE id = $1',
      [usuarioId, usuario.turnos ?? ['MANANA', 'TARDE', 'NOCHE']],
    );
  }

  // Carnet digital (§4.2): uno por usuario, código Code 128 y vigencia de un año.
  const codigoBarras = `UNI-${usuario.codigo}`;
  await cliente.query(
    `INSERT INTO carnet (usuario_id, codigo_barras, estado, vigente_hasta)
     VALUES ($1, $2, 'ACTIVO', (now() + interval '1 year')::date)
     ON CONFLICT (codigo_barras) DO UPDATE SET usuario_id = EXCLUDED.usuario_id,
       vigente_hasta = EXCLUDED.vigente_hasta`,
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

/** Entrega e intento de ejemplo en actividades que ya existían de una pasada anterior. */
async function sembrarActividadesRealizadasDemo(cliente: PoolClient): Promise<void> {
  // Juan (primer estudiante) tiene entregas de tareas: no debe verlas en «Próximas entregas».
  await cliente.query(
    `INSERT INTO entrega (id, actividad_id, estudiante_id, texto, adjuntos, creada_en_cliente, estado)
     SELECT gen_random_uuid(), act.id, est.estudiante_id,
            'Entrega de demostración con archivo adjunto.',
            '[{"objetoKey":"aulas/demo/guia-unidad.pdf","nombre":"guia-unidad.pdf","mime":"application/pdf","tamano":860}]'::jsonb,
            now() - interval '1 day', 'ENVIADA'
     FROM actividad act
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN LATERAL (
       SELECT i.estudiante_id FROM inscripcion i
       JOIN usuario u ON u.id = i.estudiante_id
       WHERE i.grupo_id = au.grupo_id AND i.estado = 'ACTIVA'
       ORDER BY (u.correo LIKE 'juan%') DESC, u.correo LIMIT 1
     ) est ON true
     WHERE act.tipo = 'TAREA'
     ON CONFLICT (actividad_id, estudiante_id) DO NOTHING`,
  );
  await cliente.query(
    `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
     SELECT e.actividad_id, i.id, 4.2, 'Buen trabajo en la demostración'
     FROM entrega e
     JOIN actividad act ON act.id = e.actividad_id
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN grupo g ON g.id = au.grupo_id
     JOIN inscripcion i ON i.grupo_id = g.id AND i.estudiante_id = e.estudiante_id
     ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
  );

  // María (segunda estudiante) ya respondió los cuestionarios: tampoco se le recuerdan.
  await cliente.query(
    `INSERT INTO intento_cuestionario (actividad_id, estudiante_id, respuestas, puntaje)
     SELECT act.id, est.estudiante_id, res.respuestas, 5.0
     FROM actividad act
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN LATERAL (
       SELECT i.estudiante_id FROM inscripcion i
       JOIN usuario u ON u.id = i.estudiante_id
       WHERE i.grupo_id = au.grupo_id AND i.estado = 'ACTIVA'
       ORDER BY (u.correo LIKE 'maria%') DESC, u.correo DESC LIMIT 1
     ) est ON true
     CROSS JOIN LATERAL (
       SELECT jsonb_object_agg(p.id::text, jsonb_build_array(o.id::text)) AS respuestas
       FROM pregunta p
       JOIN opcion_respuesta o ON o.pregunta_id = p.id AND o.es_correcta
       WHERE p.actividad_id = act.id
     ) res
     WHERE act.tipo = 'CUESTIONARIO' AND res.respuestas IS NOT NULL
     ON CONFLICT (actividad_id, estudiante_id) DO NOTHING`,
  );
  await cliente.query(
    `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
     SELECT ic.actividad_id, i.id, 5.0, 'Autocalificado por el cuestionario'
     FROM intento_cuestionario ic
     JOIN actividad act ON act.id = ic.actividad_id
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN grupo g ON g.id = au.grupo_id
     JOIN inscripcion i ON i.grupo_id = g.id AND i.estudiante_id = ic.estudiante_id
     ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
  );

  // Materiales de ejemplo propios de las actividades (no de los contenidos de la unidad).
  await cliente.query(
    `INSERT INTO actividad_recurso (actividad_id, objeto_key, nombre, mime, tamano, subido_por)
     SELECT act.id, 'aulas/demo/guia-unidad.pdf', 'Guía de la actividad.pdf',
            'application/pdf', 860, g.docente_id
     FROM actividad act
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN grupo g ON g.id = au.grupo_id
     WHERE act.tipo IN ('TAREA', 'CUESTIONARIO')
       AND NOT EXISTS (
         SELECT 1 FROM actividad_recurso r
         WHERE r.actividad_id = act.id AND r.objeto_key = 'aulas/demo/guia-unidad.pdf'
       )`,
  );

  // Nota de corte coherente con las calificaciones de ejemplo.
  await cliente.query(
    `INSERT INTO nota_corte (inscripcion_id, corte_id, nota_calculada)
     SELECT c.inscripcion_id, a.corte_id,
            ROUND(SUM(c.nota * a.peso_porcentual) / NULLIF(SUM(a.peso_porcentual), 0), 2)
     FROM calificacion c JOIN actividad a ON a.id = c.actividad_id
     GROUP BY c.inscripcion_id, a.corte_id
     ON CONFLICT (inscripcion_id, corte_id)
     DO UPDATE SET nota_calculada = EXCLUDED.nota_calculada, actualizada_en = now()`,
  );
}

/** Aula virtual completa: 3 cortes, 3 unidades, materiales, actividades y notas de ejemplo. */
async function sembrarAulaVirtualDemo(
  cliente: PoolClient,
  datos: {
    grupoId: string;
    nombre: string;
    docenteUid?: string;
    estudiantes: UsuarioSembrado[];
    curso: { nombre: string; codigoCurso: string };
  },
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
  const patronActividad = (titulo: string): number => {
    const codigo = Number(datos.curso.codigoCurso.replace(/\D/g, '')) || 0;
    const suma = [...titulo].reduce((total, letra) => total + letra.charCodeAt(0), 0);
    return (codigo + suma) % 4;
  };

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
    { numero: 2, titulo: 'Aplicación práctica y casos reales' },
    { numero: 3, titulo: 'Proyecto integrador y evaluación final' },
  ] as const;

  const contenidosPorUnidad: Record<number, Array<{
    tipo: string;
    titulo: string;
    objetoKey?: string;
    url?: string;
    mime?: string;
    descripcion?: string;
  }>> = {
    1: [
      {
        tipo: 'PDF',
        titulo: `Guía de estudio · ${datos.curso.nombre}`,
        objetoKey: 'aulas/demo/guia-unidad.pdf',
        mime: 'application/pdf',
        descripcion: 'Material base de la unidad 1',
      },
      {
        tipo: 'ENLACE',
        titulo: 'Documentación y recursos recomendados',
        url: 'https://developer.mozilla.org/es/',
      },
      {
        tipo: 'DOCUMENTO',
        titulo: 'Reglamento y acuerdos del curso',
        objetoKey: 'aulas/demo/reglamento.pdf',
        mime: 'application/pdf',
        descripcion: 'Normas de participación, entregas y evaluación',
      },
    ],
    2: [
      {
        tipo: 'VIDEO',
        titulo: 'Video de la unidad 2',
        url: 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
      },
      {
        tipo: 'ANUNCIO',
        titulo: 'Recordatorio de la entrega de la unidad',
        descripcion: 'Revisa las fechas de cierre en la sección de actividades.',
      },
      {
        tipo: 'PDF',
        titulo: 'Casos de estudio para el taller',
        objetoKey: 'aulas/demo/guia-unidad.pdf',
        mime: 'application/pdf',
        descripcion: 'Casos que se trabajan en el taller de la unidad 2',
      },
    ],
    3: [
      {
        tipo: 'PDF',
        titulo: 'Lineamientos del proyecto final',
        objetoKey: 'aulas/demo/guia-unidad.pdf',
        mime: 'application/pdf',
        descripcion: 'Estructura, entregables y rúbrica del proyecto',
      },
      {
        tipo: 'ENLACE',
        titulo: 'Plantilla para el proyecto',
        url: 'https://developer.mozilla.org/es/docs/Learn',
      },
    ],
  };

  for (const unidad of unidades) {
    const filaUnidad = await cliente.query<{ id: string }>(
      `INSERT INTO unidad (aula_id, numero, titulo) VALUES ($1, $2, $3)
       ON CONFLICT (aula_id, numero) DO UPDATE SET titulo = EXCLUDED.titulo
       RETURNING id`,
      [aulaId, unidad.numero, unidad.titulo],
    );
    const unidadId = filaUnidad.rows[0]!.id;

    for (const contenido of contenidosPorUnidad[unidad.numero] ?? []) {
      const existe = await cliente.query(
        'SELECT 1 FROM contenido WHERE unidad_id = $1 AND titulo = $2',
        [unidadId, contenido.titulo],
      );
      if ((existe.rowCount ?? 0) > 0) continue;
      await cliente.query(
        `INSERT INTO contenido (unidad_id, tipo, titulo, descripcion, objeto_key, url_externa, mime)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          unidadId,
          contenido.tipo,
          contenido.titulo,
          contenido.descripcion ?? null,
          contenido.objetoKey ?? null,
          contenido.url ?? null,
          contenido.mime ?? null,
        ],
      );
    }

    const actividades = (
      unidad.numero === 1
        ? [
            { tipo: 'TAREA', titulo: 'Taller de la unidad 1', peso: 40, corte: 1, dias: -12 },
            { tipo: 'CUESTIONARIO', titulo: 'Cuestionario de la unidad 1', peso: 30, corte: 1, dias: -9 },
            { tipo: 'TAREA', titulo: 'Informe de laboratorio', peso: 30, corte: 1, dias: -5 },
          ]
        : unidad.numero === 2
          ? [
              { tipo: 'FORO', titulo: 'Foro de discusión: casos reales', peso: 40, corte: 2, dias: 7 },
              { tipo: 'TAREA', titulo: 'Taller de la unidad 2', peso: 60, corte: 2, dias: 10 },
            ]
          : [
              { tipo: 'TAREA', titulo: 'Proyecto final', peso: 60, corte: 3, dias: 25 },
              { tipo: 'CUESTIONARIO', titulo: 'Evaluación final', peso: 40, corte: 3, dias: 28 },
            ]
    ) as ReadonlyArray<{ tipo: string; titulo: string; peso: number; corte: number; dias: number }>;

    for (const actividad of actividades) {
      const existeActividad = await cliente.query<{ id: string }>(
        'SELECT id FROM actividad WHERE unidad_id = $1 AND titulo = $2',
        [unidadId, actividad.titulo],
      );
      const instrucciones =
        actividad.tipo === 'FORO'
          ? 'Participa con al menos dos aportes y responde a un compañero.'
          : 'Actividad de demostración con datos ficticios.';
      const cierraEn = new Date(Date.now() + actividad.dias * 86_400_000).toISOString();
      if ((existeActividad.rowCount ?? 0) > 0) {
        // Semillas anteriores ya crearon la actividad: se normalizan pesos, corte y fecha.
        await cliente.query(
          `UPDATE actividad SET instrucciones = $2, cierra_en = $3::timestamptz,
             corte_id = $4, peso_porcentual = $5, revision_permitida = $6
           WHERE id = $1`,
          [
            existeActividad.rows[0]!.id,
            instrucciones,
            cierraEn,
            cortes[actividad.corte],
            actividad.peso,
            actividad.tipo === 'CUESTIONARIO',
          ],
        );
        continue;
      }

      const filaActividad = await cliente.query<{ id: string }>(
        `INSERT INTO actividad (unidad_id, tipo, titulo, instrucciones, cierra_en, corte_id, peso_porcentual, revision_permitida)
         VALUES ($1, $2, $3, $4, $5::timestamptz, $6, $7, $8)
         RETURNING id`,
        [
          unidadId,
          actividad.tipo,
          actividad.titulo,
          instrucciones,
          cierraEn,
          cortes[actividad.corte],
          actividad.peso,
          actividad.tipo === 'CUESTIONARIO',
        ],
      );
      const actividadId = filaActividad.rows[0]?.id;
      if (!actividadId) continue;

      if (actividad.tipo === 'TAREA' || actividad.tipo === 'CUESTIONARIO') {
        await cliente.query(
          `INSERT INTO actividad_recurso (actividad_id, objeto_key, nombre, mime, tamano, subido_por)
           SELECT $1, 'aulas/demo/guia-unidad.pdf', 'Guía de la actividad.pdf',
                  'application/pdf', 860, g.docente_id
           FROM aula au JOIN grupo g ON g.id = au.grupo_id
           WHERE au.id = $2
             AND NOT EXISTS (
               SELECT 1 FROM actividad_recurso r
               WHERE r.actividad_id = $1 AND r.objeto_key = 'aulas/demo/guia-unidad.pdf'
             )`,
          [actividadId, aulaId],
        );
      }

      if (actividad.tipo === 'CUESTIONARIO') {
        const preguntasCorrectas: Array<{ preguntaId: string; opcionCorrecta: string }> = [];
        for (let orden = 1; orden <= 3; orden += 1) {
          const pregunta = await cliente.query<{ id: string }>(
            `INSERT INTO pregunta (actividad_id, enunciado, orden) VALUES ($1, $2, $3) RETURNING id`,
            [
              actividadId,
              orden === 1
                ? '¿Cuál es el objetivo principal de esta unidad?'
                : orden === 2
                  ? '¿Qué herramienta se usa en el ejemplo de la muestra?'
                  : '¿Cuál de estas afirmaciones es correcta?',
              orden,
            ],
          );
          const preguntaId = pregunta.rows[0]!.id;
          const textos = ['Comprender y aplicar los conceptos', 'Un editor de texto', 'Las tres opciones anteriores'];
          const opciones: string[] = [];
          for (const [indice, texto] of textos.entries()) {
            const opcion = await cliente.query<{ id: string }>(
              `INSERT INTO opcion_respuesta (pregunta_id, texto, es_correcta, orden) VALUES ($1, $2, $3, $4) RETURNING id`,
              [preguntaId, texto, indice === 0, indice + 1],
            );
            opciones.push(opcion.rows[0]!.id);
          }
          preguntasCorrectas.push({ preguntaId, opcionCorrecta: opciones[0]! });
        }

        // Intentos de ejemplo: varían por curso y actividad; algunos cuestionarios quedan sin
        // responder y otros solo con un intento incompleto.
        const patronIntento = patronActividad(actividad.titulo);
        const intentosDemo =
          patronIntento === 0
            ? []
            : [
                { estudiante: datos.estudiantes[1] ?? datos.estudiantes[0], puntaje: 5.0, nota: 5.0, completa: true },
                ...(patronIntento >= 2
                  ? [{ estudiante: datos.estudiantes[3] ?? datos.estudiantes[0], puntaje: 3.5, nota: 3.5, completa: false }]
                  : []),
              ].filter((intento) => intento.estudiante);

        for (const intento of intentosDemo) {
          const respuestas: Record<string, string[]> = {};
          for (const [indice, pregunta] of preguntasCorrectas.entries()) {
            respuestas[pregunta.preguntaId] =
              intento.completa || indice === 0 ? [pregunta.opcionCorrecta] : [];
          }
          await cliente.query(
            `INSERT INTO intento_cuestionario (actividad_id, estudiante_id, respuestas, puntaje)
             VALUES ($1, $2, $3::jsonb, $4)
             ON CONFLICT (actividad_id, estudiante_id) DO NOTHING`,
            [actividadId, intento.estudiante!.id, JSON.stringify(respuestas), intento.puntaje],
          );
          const inscripcionIntento = await cliente.query<{ id: string }>(
            'SELECT id FROM inscripcion WHERE estudiante_id = $1 AND grupo_id = $2',
            [intento.estudiante!.id, datos.grupoId],
          );
          const inscripcionId = inscripcionIntento.rows[0]?.id;
          if (inscripcionId) {
            await cliente.query(
              `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
              [
                actividadId,
                inscripcionId,
                intento.nota,
                intento.completa
                  ? 'Respuestas correctas en su mayoría.'
                  : 'Revisa los conceptos de la unidad; faltan respuestas.',
              ],
            );
          }
        }
      }

      if (actividad.tipo === 'TAREA') {
        const notas = [4.5, 3.8];
        const comentarios = [
          'Entrega completa y bien sustentada.',
          'Cumple con lo solicitado; revisa la presentación.',
        ];
        const cantidadEntregas = patronActividad(actividad.titulo);
        const estudiantesEntrega = datos.estudiantes.slice(0, cantidadEntregas);
        for (const [indice, estudiante] of estudiantesEntrega.entries()) {
          const inscripcion = await cliente.query<{ id: string }>(
            'SELECT id FROM inscripcion WHERE estudiante_id = $1 AND grupo_id = $2',
            [estudiante.id, datos.grupoId],
          );
          const inscripcionId = inscripcion.rows[0]?.id;
          if (!inscripcionId) continue;
          const entregada = await cliente.query(
            `INSERT INTO entrega (id, actividad_id, estudiante_id, texto, adjuntos, creada_en_cliente, estado)
             VALUES ($1, $2, $3, $4, $5::jsonb, $6::timestamptz, 'ENVIADA')
             ON CONFLICT (actividad_id, estudiante_id) DO NOTHING
             RETURNING id`,
            [
              randomUUID(),
              actividadId,
              estudiante.id,
              indice === 0
                ? 'Entrega de demostración: revisa el archivo adjunto.'
                : 'Trabajo desarrollado según la guía de la unidad.',
              JSON.stringify([
                {
                  objetoKey: 'aulas/demo/guia-unidad.pdf',
                  nombre: 'guia-unidad.pdf',
                  mime: 'application/pdf',
                  tamano: 860,
                },
              ]),
              new Date(Date.now() - (indice + 1) * 86_400_000).toISOString(),
            ],
          );
          // Algunas entregas quedan sin calificar y algunas tareas sin entregar.
          if (entregada.rowCount && indice < Math.max(0, cantidadEntregas - 1)) {
            await cliente.query(
              `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
              [actividadId, inscripcionId, notas[indice], comentarios[indice]],
            );
          }
        }
      }
    }
  }
}

/** Evidencias variables: algunas tareas y cuestionarios quedan sin responder en los tres cortes. */
async function sembrarEvidenciasVariadas(cliente: PoolClient): Promise<void> {
  const actividades = await cliente.query<{
    actividad_id: string;
    tipo: string;
    titulo: string;
    codigo_curso: string;
    grupo_id: string;
  }>(
    `SELECT act.id AS actividad_id, act.tipo, act.titulo, g.codigo_curso, g.id AS grupo_id
     FROM actividad act
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN grupo g ON g.id = au.grupo_id
     WHERE g.codigo_curso = ANY($1::text[])
       AND act.tipo IN ('TAREA', 'CUESTIONARIO')
     ORDER BY g.codigo_curso, act.titulo`,
    [CURSOS.map((curso) => curso.codigoCurso)],
  );
  const numero = (texto: string): number =>
    [...texto].reduce((total, letra) => total + letra.charCodeAt(0), 0);

  for (const actividad of actividades.rows) {
    const codigo = Number(actividad.codigo_curso.replace(/\D/g, '')) || 0;
    const patron = (codigo + numero(actividad.titulo)) % 4;
    const estudiantes = await cliente.query<{ estudiante_id: string; inscripcion_id: string }>(
      `SELECT i.estudiante_id, i.id AS inscripcion_id
       FROM inscripcion i
       WHERE i.grupo_id = $1 AND i.estado = 'ACTIVA'
       ORDER BY i.estudiante_id LIMIT 3`,
      [actividad.grupo_id],
    );
    if (actividad.tipo === 'TAREA') {
      const notas = [4.5, 3.8];
      for (const [indice, estudiante] of estudiantes.rows.slice(0, patron).entries()) {
        const entregada = await cliente.query(
          `INSERT INTO entrega (id, actividad_id, estudiante_id, texto, adjuntos, creada_en_cliente, estado)
           VALUES ($1, $2, $3, $4, $5::jsonb, $6::timestamptz, 'ENVIADA')
           ON CONFLICT (actividad_id, estudiante_id) DO NOTHING RETURNING id`,
          [
            randomUUID(),
            actividad.actividad_id,
            estudiante.estudiante_id,
            indice === 0
              ? 'Entrega de demostración: revisa el archivo adjunto.'
              : 'Trabajo desarrollado según la guía de la unidad.',
            JSON.stringify([
              {
                objetoKey: 'aulas/demo/guia-unidad.pdf',
                nombre: 'guia-unidad.pdf',
                mime: 'application/pdf',
                tamano: 860,
              },
            ]),
            new Date(Date.now() - (indice + 1) * 86_400_000).toISOString(),
          ],
        );
        if (entregada.rowCount && indice < Math.max(0, patron - 1)) {
          await cliente.query(
            `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
            [
              actividad.actividad_id,
              estudiante.inscripcion_id,
              notas[Math.min(indice, notas.length - 1)],
              'Entrega de demostración calificada.',
            ],
          );
        }
      }
    } else if (patron > 0) {
      const intentos = estudiantes.rows.slice(0, Math.min(patron, 2));
      for (const [indice, estudiante] of intentos.entries()) {
        const respuestas = await cliente.query<{ respuestas: Record<string, string[]> | null }>(
          `SELECT jsonb_object_agg(p.id::text, jsonb_build_array(o.id::text)) AS respuestas
           FROM pregunta p
           JOIN opcion_respuesta o ON o.pregunta_id = p.id AND o.es_correcta
           WHERE p.actividad_id = $1`,
          [actividad.actividad_id],
        );
        if (!respuestas.rows[0]?.respuestas) continue;
        await cliente.query(
          `INSERT INTO intento_cuestionario (actividad_id, estudiante_id, respuestas, puntaje)
           VALUES ($1, $2, $3::jsonb, $4)
           ON CONFLICT (actividad_id, estudiante_id) DO NOTHING`,
          [
            actividad.actividad_id,
            estudiante.estudiante_id,
            JSON.stringify(respuestas.rows[0].respuestas),
            indice === 0 ? 5.0 : 3.5,
          ],
        );
        await cliente.query(
          `INSERT INTO calificacion (actividad_id, inscripcion_id, nota, retroalimentacion)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (actividad_id, inscripcion_id) DO NOTHING`,
          [
            actividad.actividad_id,
            estudiante.inscripcion_id,
            indice === 0 ? 5.0 : 3.5,
            'Intento de cuestionario de demostración.',
          ],
        );
      }
    }
  }
}


async function sembrarComunicacionDemo(): Promise<void> {
  if (getApps().length === 0) {
    log('Sin Firebase: se omite el espejo de foros y los anuncios de Firestore');
    return;
  }
  const db = getFirestore();

  const foros = await pool.query<{
    foro_id: string;
    aula_id: string;
    miembros: string[] | null;
    docentes: string[] | null;
  }>(
    `SELECT act.id AS foro_id, au.id AS aula_id,
            (SELECT COALESCE(array_agg(u.uid_firebase), '{}')
             FROM inscripcion i JOIN usuario u ON u.id = i.estudiante_id
             WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS miembros,
            (SELECT COALESCE(array_agg(u.uid_firebase), '{}')
             FROM usuario u WHERE u.id = g.docente_id) AS docentes
     FROM actividad act
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN grupo g ON g.id = au.grupo_id
     WHERE act.tipo = 'FORO'`,
  );
  for (const foro of foros.rows) {
    await db.doc(`foros_index/${foro.foro_id}`).set(
      { aula_id: foro.aula_id, miembros: foro.miembros ?? [], docentes: foro.docentes ?? [] },
      { merge: true },
    );
  }
  log(`Espejo foros_index actualizado (${foros.rows.length} foros)`);

  const aulas = await pool.query<{
    id: string;
    nombre: string;
    docente_uid: string | null;
    docente_nombre: string | null;
  }>(
    `SELECT au.id, au.nombre,
            d.uid_firebase AS docente_uid,
            d.nombres || ' ' || d.apellidos AS docente_nombre
     FROM aula au JOIN grupo g ON g.id = au.grupo_id
     LEFT JOIN usuario d ON d.id = g.docente_id`,
  );
  for (const aula of aulas.rows) {
    if (!aula.docente_uid) continue;
    const anuncios = [
      {
        id: 'anuncio-demo-bienvenida',
        titulo: 'Bienvenida al curso',
        cuerpo: 'Este es el aula virtual de demostración. Aquí encontrarás el material y las actividades.',
        importante: false,
      },
      {
        id: 'anuncio-demo-recordatorio',
        titulo: 'Recordatorio de entrega',
        cuerpo: 'Recuerda revisar la fecha de cierre de la primera tarea en la sección de actividades.',
        importante: true,
      },
    ];
    for (const anuncio of anuncios) {
      await db.doc(`anuncios/${aula.id}/items/${anuncio.id}`).set(
        {
          titulo: anuncio.titulo,
          cuerpo: anuncio.cuerpo,
          importante: anuncio.importante,
          autor_uid: aula.docente_uid,
          autor_nombre: aula.docente_nombre ?? 'Docente',
          creado_en: new Date().toISOString(),
        },
        { merge: true },
      );
      if (anuncio.importante) {
        await pool.query(
          `INSERT INTO correo_simulado (anuncio_id, destinatario, asunto, cuerpo)
           SELECT $1, i.estudiante_id, $2, $3
           FROM inscripcion i JOIN aula au ON au.grupo_id = i.grupo_id
           WHERE au.id = $4 AND i.estado = 'ACTIVA'
           ON CONFLICT (anuncio_id, destinatario) DO NOTHING`,
          [anuncio.id, anuncio.titulo, anuncio.cuerpo, aula.id],
        );
      }
    }
  }
  log(`Anuncios de demostración creados para ${aulas.rows.length} aulas`);
}

/** PDF mínimo válido para que el contenido «Guía de la unidad» se pueda descargar en la demo. */
function pdfDemostracion(titulo = 'Guia de demostracion - Uniminuto Campus App'): Buffer {
  const texto = titulo;
  const objetos = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    `<< /Length ${texto.length + 42} >>\nstream\nBT /F1 16 Tf 30 120 Td (${texto}) Tj ET\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [];
  objetos.forEach((objeto, indice) => {
    offsets.push(pdf.length);
    pdf += `${indice + 1} 0 obj\n${objeto}\nendobj\n`;
  });
  const inicioXref = pdf.length;
  pdf += `xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objetos.length + 1} /Root 1 0 R >>\nstartxref\n${inicioXref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

/** Sube los archivos de contenido de la muestra al datalake local o a R2 (si está configurado). */
async function subirArchivosDemo(): Promise<void> {
  const endpoint = process.env.S3_ENDPOINT;
  const accessKey = process.env.S3_ACCESS_KEY;
  const secretKey = process.env.S3_SECRET_KEY;
  const bucket = process.env.S3_BUCKET ?? 'campus-app';
  if (!endpoint || !accessKey || !secretKey) {
    log('Sin credenciales S3: se omite la subida de archivos de demostración');
    return;
  }
  try {
    const { S3Client, PutObjectCommand } = await import('@aws-sdk/client-s3');
    const cliente = new S3Client({
      endpoint,
      region: process.env.S3_REGION ?? 'us-east-1',
      forcePathStyle: true,
      credentials: { accessKeyId: accessKey, secretAccessKey: secretKey },
    });
    const archivosDemo: Array<{ clave: string; titulo: string }> = [
      { clave: 'aulas/demo/guia-unidad.pdf', titulo: 'Guia de estudio - Uniminuto Campus App' },
      { clave: 'aulas/demo/reglamento.pdf', titulo: 'Reglamento del curso - Uniminuto Campus App' },
    ];
    for (const archivo of archivosDemo) {
      await cliente.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: archivo.clave,
          ContentType: 'application/pdf',
          Body: pdfDemostracion(archivo.titulo),
        }),
      );
    }
    log('Archivos de demostración subidos al datalake (guía y reglamento)');
  } catch (error) {
    console.warn(
      '⚠ No se pudieron subir los archivos de demostración:',
            error instanceof Error ? error.message : error,
    );
  }
}

const aulasEliminadas: string[] = [];
const forosEliminados: string[] = [];

function programaDeAsignatura(codigo: string): string {
  if (codigo.startsWith('ADM')) return 'Administración de Empresas';
  if (codigo.startsWith('PSI')) return 'Psicología';
  return 'Ingeniería de Sistemas';
}

/** Elimina cursos y actividades con nombres de prueba creados desde la app en sesiones anteriores. */
async function limpiarDatosDePrueba(
  cliente: PoolClient,
): Promise<{ aulas: string[]; foros: string[] }> {
  const asignaturas = await cliente.query<{ id: string }>(
    `SELECT id FROM asignatura
     WHERE codigo IN ('1111111', '2221', '2341') OR lower(nombre) IN ('222211', 'lick', 'prueba')`,
  );
  const asignaturaIds = asignaturas.rows.map((fila) => fila.id);
  const grupos = asignaturaIds.length
    ? (
        await cliente.query<{ id: string; aula_id: string | null }>(
          `SELECT g.id, au.id AS aula_id FROM grupo g
           LEFT JOIN aula au ON au.grupo_id = g.id
           WHERE g.asignatura_id = ANY($1::uuid[])`,
          [asignaturaIds],
        )
      ).rows
    : [];
  const grupoIds = grupos.map((fila) => fila.id);
  const aulas = grupos.map((fila) => fila.aula_id).filter((id): id is string => Boolean(id));

  const condiciones = [
    `lower(act.titulo) IN ('sss', 'prueba', 'hfyjv', 'yjyyg', 'foro de discusión')`,
  ];
  const valores: unknown[] = [];
  if (aulas.length > 0) {
    valores.push(aulas);
    condiciones.push(
      `act.unidad_id IN (SELECT un.id FROM unidad un WHERE un.aula_id = ANY($1::uuid[]))`,
    );
  }
  const actividades = await cliente.query<{ id: string; tipo: string }>(
    `SELECT act.id, act.tipo FROM actividad act WHERE ${condiciones.join(' OR ')}`,
    valores,
  );
  const actividadIds = actividades.rows.map((fila) => fila.id);
  const foros = actividades.rows
    .filter((fila) => fila.tipo === 'FORO')
    .map((fila) => fila.id);

  if (actividadIds.length > 0) {
    await cliente.query('DELETE FROM calificacion WHERE actividad_id = ANY($1::uuid[])', [actividadIds]);
    await cliente.query('DELETE FROM intento_cuestionario WHERE actividad_id = ANY($1::uuid[])', [
      actividadIds,
    ]);
    await cliente.query('DELETE FROM entrega WHERE actividad_id = ANY($1::uuid[])', [actividadIds]);
    await cliente.query('DELETE FROM actividad_recurso WHERE actividad_id = ANY($1::uuid[])', [
      actividadIds,
    ]);
    await cliente.query('DELETE FROM actividad WHERE id = ANY($1::uuid[])', [actividadIds]);
  }
  if (aulas.length > 0) {
    await cliente.query(
      `DELETE FROM contenido WHERE unidad_id IN (SELECT id FROM unidad WHERE aula_id = ANY($1::uuid[]))`,
      [aulas],
    );
    await cliente.query('DELETE FROM unidad WHERE aula_id = ANY($1::uuid[])', [aulas]);
  }
  if (grupoIds.length > 0) {
    await cliente.query('DELETE FROM horario WHERE grupo_id = ANY($1::uuid[])', [grupoIds]);
    await cliente.query('DELETE FROM inscripcion WHERE grupo_id = ANY($1::uuid[])', [grupoIds]);
    await cliente.query('DELETE FROM aula WHERE grupo_id = ANY($1::uuid[])', [grupoIds]);
    await cliente.query('DELETE FROM grupo WHERE id = ANY($1::uuid[])', [grupoIds]);
  }
  if (asignaturaIds.length > 0) {
    await cliente.query('DELETE FROM asignatura WHERE id = ANY($1::uuid[])', [asignaturaIds]);
  }

  // El rol ADMIN_ESPACIOS se absorbió en ADMIN_ACADEMICO (D-85): limpia asignaciones viejas.
  await cliente.query(
    `DELETE FROM usuario_rol WHERE rol_id IN (SELECT id FROM rol WHERE nombre = 'ADMIN_ESPACIOS')`,
  );

  if (asignaturaIds.length > 0 || actividadIds.length > 0) {
    log(
      `Limpieza: ${asignaturaIds.length} asignatura(s) y ${actividadIds.length} actividad(es) de prueba eliminadas`,
    );
  }
  return { aulas, foros };
}

/** Borra anuncios/hilos huérfanos de Firestore de los cursos que se eliminaron. */
async function limpiarComunicacionDemo(aulas: string[], foros: string[]): Promise<void> {
  if (getApps().length === 0 || (aulas.length === 0 && foros.length === 0)) return;
  const db = getFirestore();
  for (const aulaId of aulas) {
    const items = await db.collection('anuncios').doc(aulaId).collection('items').listDocuments();
    await Promise.all(items.map((item) => item.delete()));
    await db.doc(`anuncios/${aulaId}`).delete();
  }
  for (const foroId of foros) {
    await db.doc(`foros_index/${foroId}`).delete();
    const hilos = await db.collection('foros').doc(foroId).collection('hilos').listDocuments();
    for (const hilo of hilos) {
      const mensajes = await hilo.collection('mensajes').listDocuments();
      await Promise.all(mensajes.map((mensaje) => mensaje.delete()));
      await hilo.delete();
    }
    await db.doc(`foros/${foroId}`).delete();
  }
}

/** Hilos y mensajes ficticios en los foros para que la demostración no esté vacía. */
async function sembrarHilosForoDemo(): Promise<void> {
  if (getApps().length === 0) return;
  const db = getFirestore();
  const foros = await pool.query<{
    foro_id: string;
    aula_id: string;
    docente_uid: string | null;
    docente_nombre: string | null;
  }>(
    `SELECT act.id AS foro_id, au.id AS aula_id,
            d.uid_firebase AS docente_uid,
            d.nombres || ' ' || d.apellidos AS docente_nombre
     FROM actividad act
     JOIN unidad un ON un.id = act.unidad_id
     JOIN aula au ON au.id = un.aula_id
     JOIN grupo g ON g.id = au.grupo_id
     LEFT JOIN usuario d ON d.id = g.docente_id
     WHERE act.tipo = 'FORO'`,
  );

  for (const foro of foros.rows) {
    const hilosExistentes = await db
      .collection('foros')
      .doc(foro.foro_id)
      .collection('hilos')
      .listDocuments();
    if (hilosExistentes.length > 0) continue;

    const estudiantes = await pool.query<{ uid: string; nombre: string }>(
      `SELECT u.uid_firebase AS uid, u.nombres || ' ' || u.apellidos AS nombre
       FROM inscripcion i
       JOIN usuario u ON u.id = i.estudiante_id
       JOIN aula au ON au.grupo_id = i.grupo_id
       WHERE au.id = $1 AND i.estado = 'ACTIVA'
       ORDER BY u.apellidos, u.nombres
       LIMIT 2`,
      [foro.aula_id],
    );
    const docente = {
      uid: foro.docente_uid ?? '',
      nombre: foro.docente_nombre ?? 'Docente',
    };
    const autores = [...estudiantes.rows, docente];
    const hilos = [
      {
        titulo: '¿Cómo aplicar lo visto en un caso real?',
        mensajes: [
          'Comparto un ejemplo de mi entorno para discutirlo en clase.',
          'Buen aporte; complementa la respuesta con la guía de la unidad.',
        ],
      },
      {
        titulo: 'Dudas sobre la entrega de la unidad',
        mensajes: [
          '¿La entrega debe incluir bibliografía y conclusiones?',
          'Sí: revisa la rúbrica del curso y el archivo de la actividad.',
        ],
      },
    ];

    for (const [indice, hilo] of hilos.entries()) {
      const autor = autores[indice % autores.length] ?? docente;
      const referencia = db
        .collection('foros')
        .doc(foro.foro_id)
        .collection('hilos')
        .doc(`hilo-demo-${indice + 1}`);
      await referencia.set({
        titulo: hilo.titulo,
        autor_uid: autor.uid,
        autor_nombre: autor.nombre,
        aula_id: foro.aula_id,
        foro_id: foro.foro_id,
        creado_en: new Date(Date.now() - (indice + 2) * 86_400_000).toISOString(),
      });
      for (const [orden, texto] of hilo.mensajes.entries()) {
        const autorMensaje = autores[(indice + orden + 1) % autores.length] ?? docente;
        await referencia.collection('mensajes').doc(`mensaje-demo-${orden + 1}`).set({
          texto,
          autor_uid: autorMensaje.uid,
          autor_nombre: autorMensaje.nombre,
          creado_en: new Date(Date.now() - (indice + 2) * 86_400_000 + orden * 3_600_000).toISOString(),
        });
      }
    }
  }
  log(`Hilos de foro de demostración preparados (${foros.rows.length} foros)`);
}

async function principal(): Promise<void> {
  log(`Sembrando datos contra ${new URL(env.DATABASE_URL).host}`);

  const usuariosSembrados: UsuarioSembrado[] = [];

  await enTransaccion(pool, async (cliente) => {
    log('Programas académicos, campus y periodo');
    const programaPorNombre = new Map<string, string>();
    for (const programa of PROGRAMAS) {
      programaPorNombre.set(programa.nombre, await upsertPrograma(cliente, programa.nombre));
    }
    const periodoId = await upsertPeriodo(cliente, '2026-2');

    log('Campus Calle 80 (edificios, pisos y salones)');
    await sembrarCampus(cliente);

    log('Espacios de autorecreación (cabinas y salas)');
    await sembrarEspaciosReservables(cliente);

    log('Limpieza de datos de prueba de sesiones anteriores');
    const restos = await limpiarDatosDePrueba(cliente);
    aulasEliminadas.push(...restos.aulas);
    forosEliminados.push(...restos.foros);

    log('Usuarios, roles y claims');
    for (const usuario of USUARIOS) {
      const uid = cuenta
        ? await asegurarUsuarioFirebase(usuario.correo, usuario.nombres, usuario.apellidos, [usuario.rol])
        : uidLocal(usuario.codigo);
      const programaId = usuario.programa ? programaPorNombre.get(usuario.programa) ?? null : null;
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
    const uidPorCorreo = new Map(usuariosSembrados.map((usuario) => [usuario.correo, usuario.uid]));

    log('Cursos, inscripciones, horarios y aulas virtuales');
    const cursosClave = CURSOS.map((curso) => curso.codigoCurso);
    // Reinicia las evidencias de la demo para que la variación de talleres sea reproducible.
    await cliente.query(
      `DELETE FROM calificacion WHERE actividad_id IN (
         SELECT act.id FROM actividad act
         JOIN unidad un ON un.id = act.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         WHERE g.codigo_curso = ANY($1::text[]))`,
      [cursosClave],
    );
    await cliente.query(
      `DELETE FROM intento_cuestionario WHERE actividad_id IN (
         SELECT act.id FROM actividad act
         JOIN unidad un ON un.id = act.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         WHERE g.codigo_curso = ANY($1::text[]))`,
      [cursosClave],
    );
    await cliente.query(
      `DELETE FROM entrega WHERE actividad_id IN (
         SELECT act.id FROM actividad act
         JOIN unidad un ON un.id = act.unidad_id
         JOIN aula au ON au.id = un.aula_id
         JOIN grupo g ON g.id = au.grupo_id
         WHERE g.codigo_curso = ANY($1::text[]))`,
      [cursosClave],
    );
    await cliente.query(
      `DELETE FROM nota_corte WHERE inscripcion_id IN (
         SELECT i.id FROM inscripcion i JOIN grupo g ON g.id = i.grupo_id
         WHERE g.codigo_curso = ANY($1::text[]))`,
      [cursosClave],
    );
    // Sincroniza los horarios exactamente con la semilla (evita franjas viejas duplicadas).
    await cliente.query(
      `DELETE FROM horario WHERE grupo_id IN (
         SELECT g.id FROM grupo g WHERE g.codigo_curso = ANY($1::text[]))`,
      [cursosClave],
    );
    // Sincroniza la matrícula exactamente con la semilla: retira estudiantes de pasadas anteriores.
    await cliente.query(
      `DELETE FROM inscripcion WHERE grupo_id IN (
         SELECT g.id FROM grupo g WHERE g.codigo_curso = ANY($1::text[]))`,
      [cursosClave],
    );

    const asignaturasProcesadas = new Set<string>();
    for (const curso of CURSOS) {
      if (!asignaturasProcesadas.has(curso.asignatura)) {
        const programaId = programaPorNombre.get(programaDeAsignatura(curso.asignatura)) ?? null;
        await cliente.query(
          `INSERT INTO asignatura (codigo, nombre, creditos, requiere_laboratorio, programa_id)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre, creditos = EXCLUDED.creditos,
             requiere_laboratorio = EXCLUDED.requiere_laboratorio, programa_id = EXCLUDED.programa_id`,
          [curso.asignatura, curso.nombre, curso.creditos, curso.requiereLaboratorio, programaId],
        );
        asignaturasProcesadas.add(curso.asignatura);
      }
      const filaAsignatura = await cliente.query<{ id: string }>(
        'SELECT id FROM asignatura WHERE codigo = $1',
        [curso.asignatura],
      );
      const asignaturaId = filaAsignatura.rows[0]!.id;

      const filaGrupo = await cliente.query<{ id: string }>(
        `INSERT INTO grupo (asignatura_id, periodo_id, docente_id, numero_grupo, codigo_curso)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (asignatura_id, periodo_id, numero_grupo)
         DO UPDATE SET docente_id = EXCLUDED.docente_id, codigo_curso = EXCLUDED.codigo_curso
         RETURNING id`,
        [
          asignaturaId,
          periodoId,
          idPorCorreo.get(curso.docente) ?? null,
          curso.numero,
          curso.codigoCurso,
        ],
      );
      const grupoId = filaGrupo.rows[0]!.id;
      const estudiantes = usuariosSembrados.filter((usuario) =>
        curso.estudiantes.includes(usuario.correo),
      );

      for (const estudiante of estudiantes) {
        await cliente.query(
          `INSERT INTO inscripcion (estudiante_id, grupo_id, estado) VALUES ($1, $2, 'ACTIVA')
           ON CONFLICT (estudiante_id, grupo_id) DO UPDATE SET estado = 'ACTIVA'`,
          [estudiante.id, grupoId],
        );
      }

      await sembrarAulaVirtualDemo(cliente, {
        grupoId,
        nombre: `${curso.nombre} · Curso ${curso.codigoCurso}`,
        docenteUid: uidPorCorreo.get(curso.docente),
        estudiantes,
        curso,
      });

      for (const [dia, inicio, fin, salonCodigo] of curso.horarios) {
        const salon = await cliente.query<{ id: string }>(
          'SELECT id FROM salon WHERE codigo = $1',
          [salonCodigo],
        );
        if (!salon.rows[0]) throw new Error(`El salón ${salonCodigo} no existe en la semilla`);
        await cliente.query(
          `INSERT INTO horario (grupo_id, salon_id, dia_semana, hora_inicio, hora_fin)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (grupo_id, dia_semana, hora_inicio)
           DO UPDATE SET salon_id = EXCLUDED.salon_id, hora_fin = EXCLUDED.hora_fin`,
          [grupoId, salon.rows[0].id, dia, inicio, fin],
        );
      }
    }

    log('Limpieza de horarios/inscripciones de cursos que ya no están en la semilla');
    await cliente.query(
      `DELETE FROM horario WHERE grupo_id IN (
         SELECT g.id FROM grupo g JOIN periodo p ON p.id = g.periodo_id
         WHERE p.codigo = '2026-2'
           AND g.codigo_curso NOT IN (SELECT unnest($1::text[]))
       )`,
      [CURSOS.map((curso) => curso.codigoCurso)],
    );
    await cliente.query(
      `DELETE FROM inscripcion WHERE grupo_id IN (
         SELECT g.id FROM grupo g JOIN periodo p ON p.id = g.periodo_id
         WHERE p.codigo = '2026-2'
           AND g.codigo_curso NOT IN (SELECT unnest($1::text[]))
       )`,
      [CURSOS.map((curso) => curso.codigoCurso)],
    );

    log('Entregas e intentos de ejemplo (actividades ya realizadas)');
    await sembrarEvidenciasVariadas(cliente);
    // La variación de talleres la genera sembrarAulaVirtualDemo por curso; se recalcula la nota
    // de corte de todas las evidencias creadas.
    await cliente.query(
      `INSERT INTO nota_corte (inscripcion_id, corte_id, nota_calculada)
       SELECT c.inscripcion_id, a.corte_id,
              ROUND(SUM(c.nota * a.peso_porcentual) / NULLIF(SUM(a.peso_porcentual), 0), 2)
       FROM calificacion c JOIN actividad a ON a.id = c.actividad_id
       GROUP BY c.inscripcion_id, a.corte_id
       ON CONFLICT (inscripcion_id, corte_id)
       DO UPDATE SET nota_calculada = EXCLUDED.nota_calculada, actualizada_en = now()`,
    );

    // Datos de demostración que se actualizan en cada pasada de la semilla.
    await cliente.query(`UPDATE actividad SET revision_permitida = true WHERE tipo = 'CUESTIONARIO'`);
    await cliente.query(
      `UPDATE actividad SET formatos_permitidos = ARRAY['pdf','png','docx'] WHERE tipo = 'TAREA'`,
    );

    log('Incidencias de demostración');
    const estudiantesDemo = usuariosSembrados.filter((usuario) => usuario.rol === 'ESTUDIANTE');
    const incidenciasDemo = [
      { descripcion: 'El lector de la entrada del Edificio B no reconoce el QR del carnet', estado: 'ABIERTA', resolucion: null },
      { descripcion: 'La sala de autorecreación B-301 aparece ocupada sin reserva', estado: 'EN_PROCESO', resolucion: null },
      { descripcion: 'No puedo abrir el PDF de la guía de la unidad 1', estado: 'RESUELTA', resolucion: 'Se volvió a publicar el material en el aula virtual.' },
      { descripcion: 'El aula virtual muestra una entrega marcada como no entregada', estado: 'ABIERTA', resolucion: null },
      { descripcion: 'El horario del curso 2235 choca con una clase de otro programa', estado: 'EN_PROCESO', resolucion: null },
      { descripcion: 'La aplicación se cerró al descargar un archivo de una actividad', estado: 'RESUELTA', resolucion: 'Se corrigió la descarga de archivos adjuntos.' },
      { descripcion: 'Solicito actualizar mi correo institucional en el perfil', estado: 'ABIERTA', resolucion: null },
    ];
    for (const [indice, incidencia] of incidenciasDemo.entries()) {
      const existe = await cliente.query('SELECT 1 FROM incidencia WHERE descripcion = $1', [
        incidencia.descripcion,
      ]);
      if ((existe.rowCount ?? 0) === 0) {
        const estudiante = estudiantesDemo[indice % Math.max(estudiantesDemo.length, 1)];
        if (!estudiante) continue;
        await cliente.query(
          `INSERT INTO incidencia (usuario_id, descripcion, estado, resolucion)
           VALUES ($1, $2, $3, $4)`,
          [estudiante.id, incidencia.descripcion, incidencia.estado, incidencia.resolucion],
        );
      }
    }
  });

  log('Espejo de foros y anuncios de Firestore');
  await limpiarComunicacionDemo(aulasEliminadas, forosEliminados);
  await sembrarComunicacionDemo();
  await sembrarHilosForoDemo();

  log('Archivos de contenido de demostración');
  await subirArchivosDemo();

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
