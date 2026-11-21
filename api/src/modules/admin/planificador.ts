import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';

interface SalonPlan {
  id: string;
  codigo: string;
  tipo: string;
  capacidad: number;
}

interface HorarioPlan {
  id: string;
  grupoId: string;
  asignatura: string;
  codigoAsignatura: string;
  codigoCurso: string;
  grupo: string;
  periodo: string;
  salonId: string;
  salon: string;
  diaSemana: number;
  horaInicio: string;
  horaFin: string;
  estudiantes: number;
  requiereLaboratorio: boolean;
}

interface GrupoPlan {
  id: string;
  asignatura: string;
  codigoAsignatura: string;
  codigoCurso: string;
  grupo: string;
  periodo: string;
  docente: string | null;
  estudiantes: number;
  requiereLaboratorio: boolean;
  horarios: HorarioPlan[];
}

interface ResultadoPlanificacion {
  totalHorarios: number;
  asignados: number;
  movidos: number;
  sinSalon: Array<{ grupo: string; asignatura: string; motivo: string }>;
}

export interface RepositorioPlanificador {
  resumen(): Promise<{ grupos: GrupoPlan[]; salones: SalonPlan[]; horarios: HorarioPlan[] }>;
  planificar(): Promise<ResultadoPlanificacion>;
  generarHorario(grupoId: string): Promise<HorarioPlan[]>;
  crearHorario(datos: {
    grupoId: string;
    diaSemana: number;
    horaInicio: string;
    horaFin: string;
  }): Promise<HorarioPlan>;
  moverHorario(
    id: string,
    datos: { salonId?: string; diaSemana?: number; horaInicio?: string; horaFin?: string },
  ): Promise<HorarioPlan>;
  eliminarHorario(id: string): Promise<boolean>;
  eliminarGrupo(id: string): Promise<boolean>;
}

const horaTexto = (valor: string | Date): string => {
  const texto = valor instanceof Date ? valor.toISOString().slice(11, 19) : String(valor);
  return texto.slice(0, 5);
};

const choca = (
  a: { diaSemana: number; horaInicio: string; horaFin: string },
  b: { diaSemana: number; horaInicio: string; horaFin: string },
): boolean => a.diaSemana === b.diaSemana && a.horaInicio < b.horaFin && a.horaFin > b.horaInicio;

/**
 * Planificador de horarios y salones (corrección de la muestra).
 *
 * Las aulas de clase se asignan solas: primero las asignaturas que necesitan equipos (solo
 * salones tipo LABORATORIO), luego por número de estudiantes y capacidad; se evita que dos
 * grupos usen el mismo salón a la misma hora. El administrador académico puede volver a
 * planificar todo o mover un horario a mano; el resultado de la planificación es interno y la
 * app solo muestra los horarios ya resueltos.
 */
export function crearRepositorioPlanificador(pool: Pool): RepositorioPlanificador {
  async function cargarSalones(): Promise<SalonPlan[]> {
    const resultado = await pool.query<{
      id: string;
      codigo: string;
      tipo: string;
      capacidad: number;
    }>(
      `SELECT s.id, s.codigo, s.tipo, s.capacidad
       FROM salon s JOIN piso pi ON pi.id = s.piso_id
       JOIN edificio e ON e.id = pi.edificio_id
       WHERE s.tipo IN ('AULA', 'LABORATORIO')
       ORDER BY s.capacidad, s.codigo`,
    );
    return resultado.rows.map((fila) => ({
      id: fila.id,
      codigo: fila.codigo,
      tipo: fila.tipo,
      capacidad: fila.capacidad,
    }));
  }

  async function cargarHorarios(): Promise<HorarioPlan[]> {
    const resultado = await pool.query<{
      id: string;
      grupo_id: string;
      asignatura: string;
      codigo_asignatura: string;
      codigo_curso: string;
      grupo: string;
      periodo: string;
      salon_id: string;
      salon: string;
      dia_semana: number;
      hora_inicio: string | Date;
      hora_fin: string | Date;
      estudiantes: number;
      requiere_laboratorio: boolean;
    }>(
      `SELECT h.id, h.grupo_id, asg.nombre AS asignatura, asg.codigo AS codigo_asignatura,
              g.codigo_curso, g.numero_grupo AS grupo, p.codigo AS periodo,
              h.salon_id, s.codigo AS salon, h.dia_semana, h.hora_inicio, h.hora_fin,
              (SELECT COUNT(*)::int FROM inscripcion i WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS estudiantes,
              asg.requiere_laboratorio
       FROM horario h
       JOIN grupo g ON g.id = h.grupo_id
       JOIN asignatura asg ON asg.id = g.asignatura_id
       JOIN periodo p ON p.id = g.periodo_id
       JOIN salon s ON s.id = h.salon_id
       ORDER BY p.codigo DESC, asg.nombre, g.codigo_curso, h.dia_semana, h.hora_inicio`,
    );
    return resultado.rows.map((fila) => ({
      id: fila.id,
      grupoId: fila.grupo_id,
      asignatura: fila.asignatura,
      codigoAsignatura: fila.codigo_asignatura,
      codigoCurso: fila.codigo_curso,
      grupo: fila.grupo,
      periodo: fila.periodo,
      salonId: fila.salon_id,
      salon: fila.salon,
      diaSemana: fila.dia_semana,
      horaInicio: horaTexto(fila.hora_inicio),
      horaFin: horaTexto(fila.hora_fin),
      estudiantes: fila.estudiantes,
      requiereLaboratorio: fila.requiere_laboratorio,
    }));
  }

  function salonSirve(salon: SalonPlan, horario: HorarioPlan): boolean {
    const tipoOk = horario.requiereLaboratorio
      ? salon.tipo === 'LABORATORIO'
      : salon.tipo !== 'OFICINA';
    const capacidadOk = horario.estudiantes === 0 || salon.capacidad >= horario.estudiantes;
    return tipoOk && capacidadOk;
  }

  /** Elige el salón libre más pequeño que sirva para el horario, evitando choques. */
  function elegirSalon(
    horario: HorarioPlan,
    salones: SalonPlan[],
    ocupacion: Array<{ salonId: string; diaSemana: number; horaInicio: string; horaFin: string }>,
    excluirSalonId?: string,
  ): SalonPlan | null {
    const candidatos = salones
      .filter((salon) => salonSirve(salon, horario))
      .filter((salon) => {
        if (excluirSalonId && salon.id === excluirSalonId) return false;
        return !ocupacion.some(
          (uso) =>
            uso.salonId === salon.id &&
            choca(
              { diaSemana: horario.diaSemana, horaInicio: horario.horaInicio, horaFin: horario.horaFin },
              uso,
            ),
        );
      })
      .sort((a, b) => a.capacidad - b.capacidad || a.codigo.localeCompare(b.codigo));
    return candidatos[0] ?? null;
  }

  async function cargarGrupo(grupoId: string) {
    const resultado = await pool.query<{
      id: string;
      asignatura: string;
      codigo_asignatura: string;
      codigo_curso: string;
      grupo: string;
      periodo: string;
      requiere_laboratorio: boolean;
      estudiantes: number;
    }>(
      `SELECT g.id, asg.nombre AS asignatura, asg.codigo AS codigo_asignatura,
              g.codigo_curso, g.numero_grupo AS grupo, p.codigo AS periodo, asg.requiere_laboratorio,
              (SELECT COUNT(*)::int FROM inscripcion i WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS estudiantes
       FROM grupo g
       JOIN asignatura asg ON asg.id = g.asignatura_id
       JOIN periodo p ON p.id = g.periodo_id
       WHERE g.id = $1`,
      [grupoId],
    );
    return resultado.rows[0] ?? null;
  }

  async function cargarHorario(id: string): Promise<HorarioPlan | null> {
    const resultado = await pool.query<{ id: string }>('SELECT id FROM horario WHERE id = $1', [id]);
    if (!resultado.rows[0]) return null;
    const todos = await cargarHorarios();
    return todos.find((horario) => horario.id === id) ?? null;
  }

  async function validarChoque(datos: {
    grupoId: string;
    salonId: string;
    diaSemana: number;
    horaInicio: string;
    horaFin: string;
    excluirHorarioId?: string;
  }): Promise<void> {
    const resultado = await pool.query<{
      salon_id: string;
      docente_id: string | null;
      estudiantes: boolean;
    }>(
      `SELECT h.salon_id, g.docente_id,
              EXISTS (
                SELECT 1 FROM inscripcion i1
                JOIN inscripcion i2 ON i2.estudiante_id = i1.estudiante_id
                WHERE i1.grupo_id = cur.id AND i2.grupo_id = g.id
                  AND i1.estado = 'ACTIVA' AND i2.estado = 'ACTIVA'
              ) AS estudiantes
       FROM horario h
       JOIN grupo g ON g.id = h.grupo_id
       JOIN grupo cur ON cur.id = $1
       WHERE h.dia_semana = $2
         AND h.hora_inicio < $5::time AND h.hora_fin > $4::time
         AND ($6::uuid IS NULL OR h.id <> $6)
         AND (
           h.salon_id = $3
           OR (cur.docente_id IS NOT NULL AND g.docente_id = cur.docente_id)
           OR EXISTS (
             SELECT 1 FROM inscripcion i1
             JOIN inscripcion i2 ON i2.estudiante_id = i1.estudiante_id
             WHERE i1.grupo_id = cur.id AND i2.grupo_id = g.id
               AND i1.estado = 'ACTIVA' AND i2.estado = 'ACTIVA'
           )
         )
       LIMIT 1`,
      [
        datos.grupoId,
        datos.diaSemana,
        datos.salonId,
        datos.horaInicio,
        datos.horaFin,
        datos.excluirHorarioId ?? null,
      ],
    );
    const choque = resultado.rows[0];
    if (!choque) return;
    if (choque.salon_id === datos.salonId) {
      throw errores.conflicto('El salón ya está ocupado en ese día y hora');
    }
    if (choque.docente_id) {
      throw errores.conflicto('El docente ya tiene otra clase en ese día y hora');
    }
    throw errores.conflicto('Algún estudiante del curso ya tiene otra clase en ese día y hora');
  }

  async function crearHorarioAutomatico(datos: {
    grupoId: string;
    diaSemana: number;
    horaInicio: string;
    horaFin: string;
  }): Promise<HorarioPlan> {
    const grupo = await cargarGrupo(datos.grupoId);
    if (!grupo) throw errores.noEncontrado('El grupo no existe');

    const [salones, horarios] = await Promise.all([cargarSalones(), cargarHorarios()]);
    const horarioNuevo: HorarioPlan = {
      id: '',
      grupoId: grupo.id,
      asignatura: grupo.asignatura,
      codigoAsignatura: grupo.codigo_asignatura,
      codigoCurso: grupo.codigo_curso,
      grupo: grupo.grupo,
      periodo: grupo.periodo,
      salonId: '',
      salon: '',
      diaSemana: datos.diaSemana,
      horaInicio: datos.horaInicio.slice(0, 5),
      horaFin: datos.horaFin.slice(0, 5),
      estudiantes: grupo.estudiantes,
      requiereLaboratorio: grupo.requiere_laboratorio,
    };

    // El grupo no puede tener dos clases en el mismo día y hora.
    if (horarios.some((horario) => horario.grupoId === datos.grupoId && choca(horario, horarioNuevo))) {
      throw errores.conflicto('El grupo ya tiene clase en ese día y hora');
    }

    const ocupacion = horarios.map((horario) => ({
      salonId: horario.salonId,
      diaSemana: horario.diaSemana,
      horaInicio: horario.horaInicio,
      horaFin: horario.horaFin,
    }));
    const salon = elegirSalon(horarioNuevo, salones, ocupacion);
    if (!salon) {
      throw errores.conflicto(
        'No hay salón libre que cumpla capacidad y equipos para ese día y hora; mueve otro horario o crea más salones',
      );
    }
    await validarChoque({
      grupoId: datos.grupoId,
      salonId: salon.id,
      diaSemana: datos.diaSemana,
      horaInicio: datos.horaInicio,
      horaFin: datos.horaFin,
    });

    const creado = await pool.query<{ id: string }>(
      `INSERT INTO horario (grupo_id, salon_id, dia_semana, hora_inicio, hora_fin)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [datos.grupoId, salon.id, datos.diaSemana, datos.horaInicio, datos.horaFin],
    );
    const horarioCreado = await cargarHorario(creado.rows[0]!.id);
    if (!horarioCreado) throw errores.conflicto('No se pudo crear el horario');
    return horarioCreado;
  }

  /**
   * Genera un horario completo (días y salones) para un curso sin horario.
   *
   * Usa los créditos como horas semanales, reparte en una o dos sesiones y respeta:
   *  - los turnos disponibles del docente (`usuario.turnos_disponibles`);
   *  - la capacidad y el tipo de salón (laboratorio cuando la asignatura lo exige);
   *  - que no se cruce con el salón, el docente ni ningún estudiante inscrito.
   */
  async function generarHorarioCompleto(grupoId: string): Promise<HorarioPlan[]> {
    const datos = await pool.query<{
      id: string;
      creditos: number;
      requiere_laboratorio: boolean;
      docente_id: string | null;
      estudiantes: number;
      turnos: string[] | null;
    }>(
      `SELECT g.id, asg.creditos, asg.requiere_laboratorio, g.docente_id,
              (SELECT COUNT(*)::int FROM inscripcion i WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS estudiantes,
              d.turnos_disponibles AS turnos
       FROM grupo g
       JOIN asignatura asg ON asg.id = g.asignatura_id
       LEFT JOIN usuario d ON d.id = g.docente_id
       WHERE g.id = $1`,
      [grupoId],
    );
    const grupo = datos.rows[0];
    if (!grupo) throw errores.noEncontrado('El curso no existe');

    const existentes = await pool.query<{ id: string }>('SELECT id FROM horario WHERE grupo_id = $1', [
      grupoId,
    ]);
    if ((existentes.rowCount ?? 0) > 0) {
      throw errores.conflicto('El curso ya tiene horario. Elimina o mueve las franjas existentes.');
    }

    const salones = (await cargarSalones()).filter((salon) => {
      const tipoOk = grupo.requiere_laboratorio ? salon.tipo === 'LABORATORIO' : salon.tipo === 'AULA';
      return tipoOk && salon.capacidad >= grupo.estudiantes;
    });
    if (salones.length === 0) {
      throw errores.conflicto('No hay salones con la capacidad o el tipo requerido para este curso');
    }

    const ventanas: Record<string, [number, number]> = {
      MANANA: [6, 12],
      TARDE: [12, 18],
      NOCHE: [18, 22],
    };
    const turnos = (grupo.turnos && grupo.turnos.length > 0
      ? grupo.turnos
      : ['MANANA', 'TARDE', 'NOCHE']) as Array<keyof typeof ventanas>;
    const rangos = turnos
      .map((turno) => ventanas[turno])
      .filter((rango): rango is [number, number] => Boolean(rango))
      .sort((a, b) => a[0] - b[0]);

    const totalHoras = Math.max(1, Math.min(6, Number(grupo.creditos)));
    const horasPrimera = Math.min(2, Math.ceil(totalHoras / 2));
    const horasSegunda = totalHoras - horasPrimera;
    const sesiones = horasSegunda > 0 ? [horasPrimera, horasSegunda] : [horasPrimera];

    const dias = [1, 3, 2, 4, 5];
    const creados: string[] = [];
    const intentarSesion = async (horas: number, indice: number): Promise<boolean> => {
      for (const dia of dias) {
        if (indice === 1 && creados.length === 1) {
          // Evita que las dos sesiones queden el mismo día.
          const primero = await pool.query<{ dia_semana: number }>(
            'SELECT dia_semana FROM horario WHERE id = $1',
            [creados[0]],
          );
          if (primero.rows[0]?.dia_semana === dia) continue;
        }
        for (const [desde, hasta] of rangos) {
          for (let inicio = desde; inicio + horas <= hasta; inicio += 1) {
            const horaInicio = `${String(inicio).padStart(2, '0')}:00`;
            const horaFin = `${String(inicio + horas).padStart(2, '0')}:00`;
            for (const salon of salones) {
              try {
                await validarChoque({
                  grupoId,
                  salonId: salon.id,
                  diaSemana: dia,
                  horaInicio,
                  horaFin,
                });
                const creado = await pool.query<{ id: string }>(
                  `INSERT INTO horario (grupo_id, salon_id, dia_semana, hora_inicio, hora_fin)
                   VALUES ($1, $2, $3, $4, $5) RETURNING id`,
                  [grupoId, salon.id, dia, horaInicio, horaFin],
                );
                creados.push(creado.rows[0]!.id);
                return true;
              } catch {
                // Sigue con el siguiente salón/franja.
              }
            }
          }
        }
      }
      return false;
    };

    for (const [indice, horas] of sesiones.entries()) {
      const ok = await intentarSesion(horas, indice);
      if (!ok) {
        for (const id of creados) await pool.query('DELETE FROM horario WHERE id = $1', [id]);
        throw errores.conflicto(
          'No se encontró una combinación de días, horas y salones sin choques para este curso',
        );
      }
    }

    const horarios = await Promise.all(creados.map((id) => cargarHorario(id)));
    return horarios.filter((horario): horario is HorarioPlan => horario !== null);
  }

  return {
    async resumen() {
      const [grupos, salones, horarios] = await Promise.all([
        pool.query<{
          id: string;
          asignatura: string;
          codigo_asignatura: string;
          codigo_curso: string;
          grupo: string;
          periodo: string;
          docente: string | null;
          estudiantes: number;
          requiere_laboratorio: boolean;
        }>(
          `SELECT g.id, asg.nombre AS asignatura, asg.codigo AS codigo_asignatura,
                  g.codigo_curso, g.numero_grupo AS grupo, p.codigo AS periodo,
                  d.nombres || ' ' || d.apellidos AS docente,
                  (SELECT COUNT(*)::int FROM inscripcion i WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS estudiantes,
                  asg.requiere_laboratorio
           FROM grupo g
           JOIN asignatura asg ON asg.id = g.asignatura_id
           JOIN periodo p ON p.id = g.periodo_id
           LEFT JOIN usuario d ON d.id = g.docente_id
           ORDER BY p.codigo DESC, asg.nombre, g.codigo_curso`,
        ),
        cargarSalones(),
        cargarHorarios(),
      ]);
      return {
        grupos: grupos.rows.map((fila) => ({
          id: fila.id,
          asignatura: fila.asignatura,
          codigoAsignatura: fila.codigo_asignatura,
          codigoCurso: fila.codigo_curso,
          grupo: fila.grupo,
          periodo: fila.periodo,
          docente: fila.docente,
          estudiantes: fila.estudiantes,
          requiereLaboratorio: fila.requiere_laboratorio,
          horarios: horarios.filter((horario) => horario.grupoId === fila.id),
        })),
        salones,
        horarios,
      };
    },

    async planificar() {
      const [salones, horarios] = await Promise.all([cargarSalones(), cargarHorarios()]);
      const resultado: ResultadoPlanificacion = {
        totalHorarios: horarios.length,
        asignados: 0,
        movidos: 0,
        sinSalon: [],
      };

      // Primero laboratorios, luego grupos más grandes: así los salones de equipos no se ocupan
      // con clases que no los necesitan.
      const orden = [...horarios].sort((a, b) => {
        if (a.requiereLaboratorio !== b.requiereLaboratorio) return a.requiereLaboratorio ? -1 : 1;
        if (a.estudiantes !== b.estudiantes) return b.estudiantes - a.estudiantes;
        return a.id.localeCompare(b.id);
      });

      const ocupacion: Array<{ salonId: string; diaSemana: number; horaInicio: string; horaFin: string }> = [];
      const cambios: Array<{ id: string; salonId: string }> = [];

      for (const horario of orden) {
        let salon = salones.find((candidato) => candidato.id === horario.salonId) ?? null;
        const actualSirve = salon !== null && salonSirve(salon, horario);
        const actualLibre =
          actualSirve &&
          !ocupacion.some(
            (uso) =>
              uso.salonId === horario.salonId &&
              choca(
                { diaSemana: horario.diaSemana, horaInicio: horario.horaInicio, horaFin: horario.horaFin },
                uso,
              ),
          );
        if (!actualLibre) {
          salon = elegirSalon(horario, salones, ocupacion);
        }
        if (!salon) {
          resultado.sinSalon.push({
            grupo: `${horario.asignatura} (curso ${horario.codigoCurso})`,
            asignatura: horario.asignatura,
            motivo: horario.requiereLaboratorio
              ? 'No hay laboratorio libre con capacidad suficiente'
              : 'No hay salón libre con capacidad suficiente',
          });
          continue;
        }
        ocupacion.push({
          salonId: salon.id,
          diaSemana: horario.diaSemana,
          horaInicio: horario.horaInicio,
          horaFin: horario.horaFin,
        });
        resultado.asignados += 1;
        if (salon.id !== horario.salonId) {
          cambios.push({ id: horario.id, salonId: salon.id });
        }
      }

      if (cambios.length > 0) {
        await withTx(pool, async (cliente) => {
          for (const cambio of cambios) {
            await cliente.query('UPDATE horario SET salon_id = $2 WHERE id = $1', [
              cambio.id,
              cambio.salonId,
            ]);
          }
        });
      }
      resultado.movidos = cambios.length;
      return resultado;
    },

    async crearHorario(datos) {
      return crearHorarioAutomatico(datos);
    },

    async generarHorario(grupoId) {
      return generarHorarioCompleto(grupoId);
    },

    async moverHorario(id, datos) {
      const horario = await cargarHorario(id);
      if (!horario) throw errores.noEncontrado('El horario no existe');
      const [salones, horarios] = await Promise.all([cargarSalones(), cargarHorarios()]);

      const diaSemana = datos.diaSemana ?? horario.diaSemana;
      const horaInicio = (datos.horaInicio ?? horario.horaInicio).slice(0, 5);
      const horaFin = (datos.horaFin ?? horario.horaFin).slice(0, 5);
      if (horaFin <= horaInicio) throw errores.datosInvalidos('La hora de fin debe ser mayor que la de inicio');

      const otros = horarios.filter((otro) => otro.id !== id);
      if (otros.some((otro) => otro.grupoId === horario.grupoId && choca(otro, { diaSemana, horaInicio, horaFin }))) {
        throw errores.conflicto('El grupo ya tiene otra clase en ese día y hora');
      }

      let salonId = datos.salonId ?? horario.salonId;
      if (datos.salonId) {
        const salon = salones.find((candidato) => candidato.id === datos.salonId);
        if (!salon) throw errores.noEncontrado('El salón no existe');
        const actualizado = { ...horario, salonId, diaSemana, horaInicio, horaFin };
        if (!salonSirve(salon, actualizado)) {
          throw errores.datosInvalidos(
            horario.requiereLaboratorio
              ? 'La asignatura necesita un laboratorio con capacidad para el grupo'
              : 'El salón no tiene capacidad suficiente para el grupo',
          );
        }
      }
      const ocupacion = otros.map((otro) => ({
        salonId: otro.salonId,
        diaSemana: otro.diaSemana,
        horaInicio: otro.horaInicio,
        horaFin: otro.horaFin,
      }));
      if (
        ocupacion.some(
          (uso) =>
            uso.salonId === salonId &&
            choca(uso, { diaSemana, horaInicio, horaFin }),
        )
      ) {
        throw errores.conflicto('El salón ya está ocupado en ese día y hora');
      }
      await validarChoque({
        grupoId: horario.grupoId,
        salonId,
        diaSemana,
        horaInicio,
        horaFin,
        excluirHorarioId: id,
      });

      await pool.query(
        `UPDATE horario SET salon_id = $2, dia_semana = $3, hora_inicio = $4, hora_fin = $5 WHERE id = $1`,
        [id, salonId, diaSemana, horaInicio, horaFin],
      );
      const actualizado = await cargarHorario(id);
      if (!actualizado) throw errores.conflicto('No se pudo actualizar el horario');
      return actualizado;
    },

    async eliminarHorario(id) {
      const resultado = await pool.query('DELETE FROM horario WHERE id = $1', [id]);
      return (resultado.rowCount ?? 0) > 0;
    },

    async eliminarGrupo(id) {
      const grupo = await cargarGrupo(id);
      if (!grupo) return false;
      return withTx(pool, async (cliente) => {
        const actividades = await cliente.query<{ id: string }>(
          `SELECT act.id FROM actividad act
           JOIN unidad un ON un.id = act.unidad_id
           JOIN aula au ON au.id = un.aula_id
           WHERE au.grupo_id = $1`,
          [id],
        );
        const ids = actividades.rows.map((fila) => fila.id);
        if (ids.length > 0) {
          await cliente.query('DELETE FROM calificacion WHERE actividad_id = ANY($1::uuid[])', [ids]);
          await cliente.query('DELETE FROM intento_cuestionario WHERE actividad_id = ANY($1::uuid[])', [ids]);
          await cliente.query('DELETE FROM entrega WHERE actividad_id = ANY($1::uuid[])', [ids]);
          await cliente.query('DELETE FROM actividad_recurso WHERE actividad_id = ANY($1::uuid[])', [ids]);
          await cliente.query('DELETE FROM actividad WHERE id = ANY($1::uuid[])', [ids]);
        }
        await cliente.query(
          'DELETE FROM contenido WHERE unidad_id IN (SELECT id FROM unidad WHERE aula_id IN (SELECT id FROM aula WHERE grupo_id = $1))',
          [id],
        );
        await cliente.query(
          'DELETE FROM unidad WHERE aula_id IN (SELECT id FROM aula WHERE grupo_id = $1)',
          [id],
        );
        await cliente.query(
          `DELETE FROM nota_corte WHERE inscripcion_id IN (SELECT id FROM inscripcion WHERE grupo_id = $1)`,
          [id],
        );
        await cliente.query('DELETE FROM inscripcion WHERE grupo_id = $1', [id]);
        await cliente.query('DELETE FROM horario WHERE grupo_id = $1', [id]);
        await cliente.query('DELETE FROM aula WHERE grupo_id = $1', [id]);
        await cliente.query('DELETE FROM corte WHERE grupo_id = $1', [id]);
        const eliminado = await cliente.query('DELETE FROM grupo WHERE id = $1', [id]);
        return (eliminado.rowCount ?? 0) > 0;
      });
    },
  };
}

const idParam = z.object({ id: z.string().uuid() });
const hora = z.string().regex(/^\d{2}:\d{2}(:\d{2})?$/);
const esquemaHorarioNuevo = z
  .object({
    diaSemana: z.number().int().min(1).max(7),
    horaInicio: hora,
    horaFin: hora,
  })
  .strict();
const esquemaHorarioMover = z
  .object({
    salonId: z.string().uuid().optional(),
    diaSemana: z.number().int().min(1).max(7).optional(),
    horaInicio: hora.optional(),
    horaFin: hora.optional(),
  })
  .strict();

/** Rutas del planificador: el admin académico administra horarios y salones. */
export function registrarRutasPlanificador(
  app: FastifyInstance,
  repo: RepositorioPlanificador,
): void {
  const admin = [app.autenticar, app.requerirRoles('ADMIN_ACADEMICO')];

  app.get('/api/v1/admin/planificacion', { preHandler: admin }, async () => repo.resumen());

  app.post('/api/v1/admin/planificacion/ejecutar', { preHandler: admin }, async () => repo.planificar());

  app.post('/api/v1/admin/grupos/:id/generar-horario', { preHandler: admin }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    return repo.generarHorario(id);
  });

  app.post('/api/v1/grupos/:id/horarios', { preHandler: admin }, async (peticion, respuesta) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaHorarioNuevo.parse(peticion.body ?? {});
    const horario = await repo.crearHorario({ grupoId: id, ...datos });
    return respuesta.code(201).send(horario);
  });

  // Se usan rutas /admin/horarios para no chocar con el CRUD clásico de /horarios (admin_espacios).
  app.put('/api/v1/admin/horarios/:id', { preHandler: admin }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaHorarioMover.parse(peticion.body ?? {});
    return repo.moverHorario(id, datos);
  });

  app.delete('/api/v1/admin/horarios/:id', { preHandler: admin }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    await repo.eliminarHorario(id);
    return { eliminado: id };
  });

  // Quitar un curso del periodo también retira horarios e inscripciones: el horario del
  // estudiante deja de mostrar esa materia (corrección de la muestra).
  app.delete('/api/v1/admin/grupos/:id', { preHandler: admin }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const eliminado = await repo.eliminarGrupo(id);
    return { eliminado: id, ok: eliminado };
  });
}
