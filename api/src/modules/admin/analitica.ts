import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import type { S3Client } from '@aws-sdk/client-s3';

import { errores } from '../../lib/errors.js';

/** Métrica de la capa curada del data lake. */
export interface MetricaAnalitica {
  categoria: string;
  clave: string;
  etiqueta: string;
  valor: number;
  detalle?: Record<string, unknown>;
}

export interface EjecucionAnalitica {
  id: string;
  generadoEn: string;
  objetoKey: string | null;
  filas: number;
  detalle: Record<string, unknown>;
}

export interface ResumenAnalitica {
  ejecucion: EjecucionAnalitica | null;
  metricas: MetricaAnalitica[];
}

export interface RepositorioAnalitica {
  ejecutar(uidActor: string): Promise<ResumenAnalitica>;
  resumen(): Promise<ResumenAnalitica>;
}

/**
 * ETL de la muestra: extrae datos operativos de CockroachDB, los deja como JSON Lines en el
 * bucket (zona procesada) y publica agregados en `analitica_metrica` (zona curada).
 *
 * No pretende ser un motor de big data: es un pipeline batch pequeño y verificable que da un uso
 * real al repositorio de objetos y alimenta el panel del administrador.
 */
export function crearRepositorioAnalitica(
  pool: Pool,
  s3: S3Client | null,
  bucket: string,
): RepositorioAnalitica {
  const cargarMetricas = async (): Promise<ResumenAnalitica> => {
    const ejecucion = await pool.query<{
      id: string;
      generado_en: string | Date;
      objeto_key: string | null;
      filas: number;
      detalle: Record<string, unknown>;
    }>(
      `SELECT id, generado_en, objeto_key, filas, detalle
       FROM analitica_ejecucion ORDER BY generado_en DESC LIMIT 1`,
    );
    const fila = ejecucion.rows[0];
    if (!fila) return { ejecucion: null, metricas: [] };
    const metricas = await pool.query<{
      categoria: string;
      clave: string;
      etiqueta: string;
      valor: string;
      detalle: Record<string, unknown>;
    }>(
      `SELECT categoria, clave, etiqueta, valor, detalle
       FROM analitica_metrica WHERE ejecucion_id = $1
       ORDER BY categoria, etiqueta`,
      [fila.id],
    );
    return {
      ejecucion: {
        id: fila.id,
        generadoEn: new Date(fila.generado_en).toISOString(),
        objetoKey: fila.objeto_key,
        filas: fila.filas,
        detalle: fila.detalle,
      },
      metricas: metricas.rows.map((metrica) => ({
        categoria: metrica.categoria,
        clave: metrica.clave,
        etiqueta: metrica.etiqueta,
        valor: Number(metrica.valor),
        detalle: metrica.detalle,
      })),
    };
  };

  return {
    resumen: cargarMetricas,

    async ejecutar(_uidActor) {
      const programas = await pool.query<{
        programa: string;
        estudiantes: number;
        cursos: number;
      }>(
        `SELECT COALESCE(pr.nombre, 'Sin programa') AS programa,
                COUNT(DISTINCT u.id)::int AS estudiantes,
                COUNT(DISTINCT g.id)::int AS cursos
         FROM programa pr
         LEFT JOIN usuario u ON u.programa_id = pr.id
         LEFT JOIN asignatura asg ON asg.programa_id = pr.id
         LEFT JOIN grupo g ON g.asignatura_id = asg.id
         GROUP BY pr.nombre ORDER BY pr.nombre`,
      );
      const cursos = await pool.query<{
        curso: string;
        asignatura: string;
        programa: string | null;
        estudiantes: number;
        promedio: string | null;
        aprobados: number;
      }>(
        `SELECT g.codigo_curso AS curso, asg.nombre AS asignatura, pr.nombre AS programa,
                COUNT(DISTINCT i.id)::int AS estudiantes,
                AVG(cal.nota) AS promedio,
                COUNT(DISTINCT CASE WHEN nc.nota_calculada >= 3 THEN nc.inscripcion_id END)::int AS aprobados
         FROM grupo g
         JOIN asignatura asg ON asg.id = g.asignatura_id
         LEFT JOIN programa pr ON pr.id = asg.programa_id
         LEFT JOIN inscripcion i ON i.grupo_id = g.id AND i.estado = 'ACTIVA'
         LEFT JOIN calificacion cal ON cal.inscripcion_id = i.id
         LEFT JOIN nota_corte nc ON nc.inscripcion_id = i.id
         GROUP BY g.codigo_curso, asg.nombre, pr.nombre
         ORDER BY asg.nombre, g.codigo_curso`,
      );
      const entregas = await pool.query<{ estado: string; total: number }>(
        `SELECT estado, COUNT(*)::int AS total FROM entrega GROUP BY estado ORDER BY estado`,
      );
      const actividades = await pool.query<{ tipo: string; total: number }>(
        `SELECT tipo, COUNT(*)::int AS total FROM actividad GROUP BY tipo ORDER BY tipo`,
      );
      const incidencias = await pool.query<{ estado: string; total: number }>(
        `SELECT estado, COUNT(*)::int AS total FROM incidencia GROUP BY estado ORDER BY estado`,
      );
      const reservas = await pool.query<{ espacio: string; total: number }>(
        `SELECT e.nombre AS espacio, COUNT(*)::int AS total
         FROM reservacion r JOIN espacio_reservable e ON e.id = r.espacio_id
         WHERE r.estado = 'CONFIRMADA' AND r.fin >= now()
         GROUP BY e.nombre ORDER BY total DESC, e.nombre`,
      );
      const acceso = await pool.query<{ total: number }>(
        `SELECT COUNT(*)::int AS total FROM evento_auditoria
         WHERE accion IN ('VALIDAR_ACCESO', 'ACCESO_VALIDADO')`,
      );

      const metricas: MetricaAnalitica[] = [];
      for (const fila of programas.rows) {
        metricas.push({
          categoria: 'programa',
          clave: `programa:${fila.programa}`,
          etiqueta: fila.programa,
          valor: fila.estudiantes,
          detalle: { estudiantes: fila.estudiantes, cursos: fila.cursos },
        });
      }
      for (const fila of cursos.rows) {
        metricas.push({
          categoria: 'curso',
          clave: `curso:${fila.curso}`,
          etiqueta: `${fila.asignatura} · ${fila.curso}`,
          valor: Number(fila.promedio ?? 0),
          detalle: {
            programa: fila.programa,
            estudiantes: fila.estudiantes,
            promedio: fila.promedio ? Number(fila.promedio) : null,
            aprobados: fila.aprobados,
          },
        });
      }
      for (const fila of entregas.rows) {
        metricas.push({
          categoria: 'entrega',
          clave: `entrega:${fila.estado}`,
          etiqueta: fila.estado,
          valor: fila.total,
        });
      }
      for (const fila of actividades.rows) {
        metricas.push({
          categoria: 'actividad',
          clave: `actividad:${fila.tipo}`,
          etiqueta: fila.tipo,
          valor: fila.total,
        });
      }
      for (const fila of incidencias.rows) {
        metricas.push({
          categoria: 'incidencia',
          clave: `incidencia:${fila.estado}`,
          etiqueta: fila.estado,
          valor: fila.total,
        });
      }
      for (const fila of reservas.rows) {
        metricas.push({
          categoria: 'reserva',
          clave: `reserva:${fila.espacio}`,
          etiqueta: fila.espacio,
          valor: fila.total,
        });
      }
      metricas.push({
        categoria: 'acceso',
        clave: 'acceso:eventos',
        etiqueta: 'Eventos de acceso registrados',
        valor: acceso.rows[0]?.total ?? 0,
      });

      // Zona procesada: un archivo JSONL inmutable por ejecución.
      const lineas = [
        ...programas.rows.map((fila) => ({ tabla: 'programas', ...fila })),
        ...cursos.rows.map((fila) => ({ tabla: 'cursos', ...fila })),
        ...entregas.rows.map((fila) => ({ tabla: 'entregas', ...fila })),
        ...actividades.rows.map((fila) => ({ tabla: 'actividades', ...fila })),
        ...incidencias.rows.map((fila) => ({ tabla: 'incidencias', ...fila })),
        ...reservas.rows.map((fila) => ({ tabla: 'reservas', ...fila })),
      ];
      const contenido = lineas.map((linea) => JSON.stringify(linea)).join('\n');
      let objetoKey: string | null = null;
      if (s3) {
        try {
          const { PutObjectCommand } = await import('@aws-sdk/client-s3');
          objetoKey = `analitica/etl/${new Date().toISOString().replace(/[:.]/g, '-')}.jsonl`;
          await s3.send(
            new PutObjectCommand({
              Bucket: bucket,
              Key: objetoKey,
              ContentType: 'application/x-ndjson',
              Body: Buffer.from(contenido, 'utf8'),
            }),
          );
        } catch (error) {
          console.warn('El ETL no pudo subir el archivo procesado al data lake:', error);
          objetoKey = null;
        }
      }

      const ejecucion = await pool.query<{ id: string; generado_en: string | Date }>(
        `INSERT INTO analitica_ejecucion (objeto_key, filas, detalle)
         VALUES ($1, $2, $3::jsonb) RETURNING id, generado_en`,
        [
          objetoKey,
          lineas.length,
          JSON.stringify({
            programas: programas.rows.length,
            cursos: cursos.rows.length,
            entregas: entregas.rows.reduce((total, fila) => total + fila.total, 0),
            metricas: metricas.length,
          }),
        ],
      );
      const ejecucionId = ejecucion.rows[0]!.id;
      for (const metrica of metricas) {
        await pool.query(
          `INSERT INTO analitica_metrica
             (ejecucion_id, categoria, clave, etiqueta, valor, detalle)
           VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
          [
            ejecucionId,
            metrica.categoria,
            metrica.clave,
            metrica.etiqueta,
            metrica.valor,
            JSON.stringify(metrica.detalle ?? {}),
          ],
        );
      }
      const resumen = await cargarMetricas();
      if (!resumen.ejecucion) throw errores.interno('No se pudo leer la ejecución de analítica');
      return resumen;
    },
  };
}

export function registrarRutasAnalitica(app: FastifyInstance, repo: RepositorioAnalitica): void {
  const admin = [app.autenticar, app.requerirRoles('ADMIN_ACADEMICO')];

  app.get('/api/v1/admin/analitica', { preHandler: admin }, async () => repo.resumen());

  app.post('/api/v1/admin/analitica/etl', { preHandler: admin }, async (peticion) =>
    repo.ejecutar(peticion.actor!.uid),
  );
}
