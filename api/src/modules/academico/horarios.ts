import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';

/** Día ISO-8601 usado por `horario.dia_semana` (D-12): 1 = lunes … 7 = domingo. */
const DIAS = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

export interface SalonUbicacion {
  codigo: string;
  tipo: string;
  capacidad: number;
  piso: number;
  edificio: string;
  edificioCodigo: string;
  sede: string;
}

export interface BloqueHorario {
  dia: number;
  diaNombre: string;
  horaInicio: string;
  horaFin: string;
  asignatura: string;
  codigo: string;
  grupo: string;
  periodo: string;
  salon: SalonUbicacion;
  docente: string | null;
}

export interface AsignaturaInscrita {
  inscripcionId: string | null;
  grupoId: string;
  asignatura: string;
  codigo: string;
  creditos: number;
  grupo: string;
  periodo: string;
  docente: string | null;
  aulaId: string | null;
  evaluada: boolean;
  estudiantes: number | null;
}

export interface RepositorioHorarios {
  miHorario(uidFirebase: string): Promise<BloqueHorario[]>;
  misAsignaturas(uidFirebase: string): Promise<AsignaturaInscrita[]>;
}

const hora = (valor: string | Date): string => {
  const texto = valor instanceof Date ? valor.toISOString().slice(11, 19) : String(valor);
  return texto.slice(0, 5);
};

/** Horario y asignaturas del usuario (estudiante inscrito o docente de los grupos). */
export function crearRepositorioHorarios(pool: Pool): RepositorioHorarios {
  return {
    async miHorario(uidFirebase) {
      const resultado = await pool.query<{
        dia_semana: number;
        hora_inicio: string;
        hora_fin: string;
        asignatura: string;
        codigo: string;
        grupo: string;
        periodo: string;
        salon: string;
        salon_tipo: string;
        capacidad: string;
        piso: number;
        edificio: string;
        edificio_codigo: string;
        sede: string;
        docente: string | null;
      }>(
        `SELECT h.dia_semana, h.hora_inicio, h.hora_fin,
                asg.nombre AS asignatura, asg.codigo,
                g.numero_grupo AS grupo, p.codigo AS periodo,
                s.codigo AS salon, s.tipo AS salon_tipo, s.capacidad,
                pi.numero AS piso, e.nombre AS edificio, e.codigo AS edificio_codigo, e.sede,
                d.nombres || ' ' || d.apellidos AS docente
         FROM horario h
         JOIN grupo g ON g.id = h.grupo_id
         JOIN asignatura asg ON asg.id = g.asignatura_id
         JOIN periodo p ON p.id = g.periodo_id
         JOIN salon s ON s.id = h.salon_id
         JOIN piso pi ON pi.id = s.piso_id
         JOIN edificio e ON e.id = pi.edificio_id
         JOIN usuario u ON u.uid_firebase = $1
         LEFT JOIN usuario d ON d.id = g.docente_id
         WHERE g.docente_id = u.id
            OR EXISTS (SELECT 1 FROM inscripcion i
                       WHERE i.grupo_id = g.id AND i.estudiante_id = u.id)
         ORDER BY h.dia_semana, h.hora_inicio`,
        [uidFirebase],
      );

      return resultado.rows.map((fila) => ({
        dia: Number(fila.dia_semana),
        diaNombre: DIAS[Number(fila.dia_semana)] ?? 'Día',
        horaInicio: hora(fila.hora_inicio),
        horaFin: hora(fila.hora_fin),
        asignatura: fila.asignatura,
        codigo: fila.codigo,
        grupo: fila.grupo,
        periodo: fila.periodo,
        salon: {
          codigo: fila.salon,
          tipo: fila.salon_tipo,
          capacidad: Number(fila.capacidad),
          piso: Number(fila.piso),
          edificio: fila.edificio,
          edificioCodigo: fila.edificio_codigo,
          sede: fila.sede,
        },
        docente: fila.docente,
      }));
    },

    async misAsignaturas(uidFirebase) {
      const comoEstudiante = await pool.query<{
        inscripcion_id: string;
        grupo_id: string;
        asignatura: string;
        codigo: string;
        creditos: string;
        grupo: string;
        periodo: string;
        docente: string | null;
        aula_id: string | null;
        evaluada: boolean;
      }>(
        `SELECT i.id AS inscripcion_id, g.id AS grupo_id, asg.nombre AS asignatura, asg.codigo,
                asg.creditos, g.numero_grupo AS grupo, p.codigo AS periodo,
                d.nombres || ' ' || d.apellidos AS docente, au.id AS aula_id,
                EXISTS (SELECT 1 FROM evaluacion_docente ev WHERE ev.inscripcion_id = i.id) AS evaluada
         FROM inscripcion i
         JOIN grupo g ON g.id = i.grupo_id
         JOIN asignatura asg ON asg.id = g.asignatura_id
         JOIN periodo p ON p.id = g.periodo_id
         JOIN usuario u ON u.id = i.estudiante_id
         LEFT JOIN usuario d ON d.id = g.docente_id
         LEFT JOIN aula au ON au.grupo_id = g.id
         WHERE u.uid_firebase = $1 AND i.estado = 'ACTIVA'
         ORDER BY asg.nombre`,
        [uidFirebase],
      );

      const comoDocente = await pool.query<{
        grupo_id: string;
        asignatura: string;
        codigo: string;
        creditos: string;
        grupo: string;
        periodo: string;
        aula_id: string | null;
        estudiantes: string;
      }>(
        `SELECT g.id AS grupo_id, asg.nombre AS asignatura, asg.codigo, asg.creditos,
                g.numero_grupo AS grupo, p.codigo AS periodo, au.id AS aula_id,
                (SELECT COUNT(*)::int FROM inscripcion i
                 WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS estudiantes
         FROM grupo g
         JOIN asignatura asg ON asg.id = g.asignatura_id
         JOIN periodo p ON p.id = g.periodo_id
         JOIN usuario u ON u.id = g.docente_id
         LEFT JOIN aula au ON au.grupo_id = g.id
         WHERE u.uid_firebase = $1
         ORDER BY asg.nombre`,
        [uidFirebase],
      );

      return [
        ...comoEstudiante.rows.map((fila) => ({
          inscripcionId: fila.inscripcion_id,
          grupoId: fila.grupo_id,
          asignatura: fila.asignatura,
          codigo: fila.codigo,
          creditos: Number(fila.creditos),
          grupo: fila.grupo,
          periodo: fila.periodo,
          docente: fila.docente,
          aulaId: fila.aula_id,
          evaluada: fila.evaluada,
          estudiantes: null,
        })),
        ...comoDocente.rows.map((fila) => ({
          inscripcionId: null,
          grupoId: fila.grupo_id,
          asignatura: fila.asignatura,
          codigo: fila.codigo,
          creditos: Number(fila.creditos),
          grupo: fila.grupo,
          periodo: fila.periodo,
          docente: null,
          aulaId: fila.aula_id,
          evaluada: false,
          estudiantes: Number(fila.estudiantes),
        })),
      ];
    },
  };
}

/** Rutas académicas de horario y asignaturas (§7.7). */
export function registrarRutasHorarios(app: FastifyInstance, repo: RepositorioHorarios): void {
  app.get('/api/v1/mi-horario', { preHandler: app.autenticar }, async (peticion) =>
    repo.miHorario(peticion.actor!.uid),
  );

  app.get('/api/v1/mis-asignaturas', { preHandler: app.autenticar }, async (peticion) =>
    repo.misAsignaturas(peticion.actor!.uid),
  );
}
