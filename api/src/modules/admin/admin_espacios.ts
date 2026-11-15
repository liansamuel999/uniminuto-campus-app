import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface EdificioAdmin {
  id: string;
  codigo: string;
  nombre: string;
  sede: string;
  pisos: number;
}

export interface PisoAdmin {
  id: string;
  edificioId: string;
  numero: number;
  tipo: string;
  salones: number;
}

export interface SalonAdmin {
  id: string;
  pisoId: string;
  codigo: string;
  tipo: string;
  capacidad: number;
}

export interface HorarioAdmin {
  id: string;
  grupoId: string;
  asignatura: string;
  grupo: string;
  periodo: string;
  salonId: string;
  salon: string;
  diaSemana: number;
  horaInicio: string;
  horaFin: string;
}

export interface RepositorioAdminEspacios {
  crearEdificio(datos: { codigo: string; nombre: string; sede: string }): Promise<EdificioAdmin>;
  actualizarEdificio(
    id: string,
    datos: { codigo?: string; nombre?: string; sede?: string },
  ): Promise<EdificioAdmin | null>;
  eliminarEdificio(id: string): Promise<boolean>;
  crearPiso(datos: { edificioId: string; numero: number; tipo: string }): Promise<PisoAdmin | null>;
  actualizarPiso(
    id: string,
    datos: { numero?: number; tipo?: string },
  ): Promise<PisoAdmin | null>;
  eliminarPiso(id: string): Promise<boolean>;
  crearSalon(datos: {
    pisoId: string;
    codigo: string;
    tipo: string;
    capacidad: number;
  }): Promise<SalonAdmin | null>;
  actualizarSalon(
    id: string,
    datos: { codigo?: string; tipo?: string; capacidad?: number },
  ): Promise<SalonAdmin | null>;
  eliminarSalon(id: string): Promise<boolean>;
  listarHorarios(filtros: { grupoId?: string; salonId?: string }): Promise<HorarioAdmin[]>;
  crearHorario(datos: {
    grupoId: string;
    salonId: string;
    diaSemana: number;
    horaInicio: string;
    horaFin: string;
  }): Promise<HorarioAdmin | null>;
  actualizarHorario(
    id: string,
    datos: {
      salonId?: string;
      diaSemana?: number;
      horaInicio?: string;
      horaFin?: string;
    },
  ): Promise<HorarioAdmin | null>;
  eliminarHorario(id: string): Promise<boolean>;
}

function esConflictoDeIntegridad(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const codigo = (error as { code?: unknown }).code;
  return codigo === '23503';
}

function esDuplicado(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const codigo = (error as { code?: unknown }).code;
  return codigo === '23505';
}

const hora = (valor: string | Date): string => {
  const texto = valor instanceof Date ? valor.toISOString().slice(11, 19) : String(valor);
  return texto.slice(0, 5);
};

const CONSULTA_HORARIO = `
  SELECT h.id, h.grupo_id, asg.nombre AS asignatura, g.numero_grupo AS grupo,
         p.codigo AS periodo, h.salon_id, s.codigo AS salon,
         h.dia_semana, h.hora_inicio, h.hora_fin
  FROM horario h
  JOIN grupo g ON g.id = h.grupo_id
  JOIN asignatura asg ON asg.id = g.asignatura_id
  JOIN periodo p ON p.id = g.periodo_id
  JOIN salon s ON s.id = h.salon_id
`;

/** CRUD del catálogo de espacios y asignación de salones a horarios (matriz §5, Fase 5). */
export function crearRepositorioAdminEspacios(pool: Pool): RepositorioAdminEspacios {
  const filaHorario = (fila: {
    id: string;
    grupo_id: string;
    asignatura: string;
    grupo: string;
    periodo: string;
    salon_id: string;
    salon: string;
    dia_semana: number;
    hora_inicio: string;
    hora_fin: string;
  }): HorarioAdmin => ({
    id: fila.id,
    grupoId: fila.grupo_id,
    asignatura: fila.asignatura,
    grupo: fila.grupo,
    periodo: fila.periodo,
    salonId: fila.salon_id,
    salon: fila.salon,
    diaSemana: Number(fila.dia_semana),
    horaInicio: hora(fila.hora_inicio),
    horaFin: hora(fila.hora_fin),
  });

  return {
    async crearEdificio(datos) {
      try {
        const resultado = await pool.query(
          `INSERT INTO edificio (codigo, nombre, sede) VALUES ($1, $2, $3)
           RETURNING id, codigo, nombre, sede`,
          [datos.codigo, datos.nombre, datos.sede],
        );
        const fila = resultado.rows[0]!;
        return { id: fila.id, codigo: fila.codigo, nombre: fila.nombre, sede: fila.sede, pisos: 0 };
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un edificio con ese código');
        throw error;
      }
    },

    async actualizarEdificio(id, datos) {
      try {
        const resultado = await pool.query(
          `UPDATE edificio SET
             codigo = COALESCE($2, codigo),
             nombre = COALESCE($3, nombre),
             sede = COALESCE($4, sede)
           WHERE id = $1
           RETURNING id, codigo, nombre, sede,
             (SELECT COUNT(*)::int FROM piso WHERE edificio_id = edificio.id) AS pisos`,
          [id, datos.codigo ?? null, datos.nombre ?? null, datos.sede ?? null],
        );
        const fila = resultado.rows[0];
        return fila
          ? { id: fila.id, codigo: fila.codigo, nombre: fila.nombre, sede: fila.sede, pisos: Number(fila.pisos) }
          : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un edificio con ese código');
        throw error;
      }
    },

    async eliminarEdificio(id) {
      try {
        const resultado = await pool.query('DELETE FROM edificio WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('El edificio tiene pisos u horarios asociados');
        }
        throw error;
      }
    },

    async crearPiso(datos) {
      try {
        const resultado = await pool.query(
          `INSERT INTO piso (edificio_id, numero, tipo) VALUES ($1, $2, $3)
           RETURNING id, edificio_id, numero, tipo`,
          [datos.edificioId, datos.numero, datos.tipo],
        );
        const fila = resultado.rows[0]!;
        return {
          id: fila.id,
          edificioId: fila.edificio_id,
          numero: Number(fila.numero),
          tipo: fila.tipo,
          salones: 0,
        };
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe ese piso en el edificio');
        if (esConflictoDeIntegridad(error)) throw errores.datosInvalidos('El edificio no existe');
        throw error;
      }
    },

    async actualizarPiso(id, datos) {
      try {
        const resultado = await pool.query(
          `UPDATE piso SET numero = COALESCE($2, numero), tipo = COALESCE($3, tipo)
           WHERE id = $1
           RETURNING id, edificio_id, numero, tipo,
             (SELECT COUNT(*)::int FROM salon WHERE piso_id = piso.id) AS salones`,
          [id, datos.numero ?? null, datos.tipo ?? null],
        );
        const fila = resultado.rows[0];
        return fila
          ? {
              id: fila.id,
              edificioId: fila.edificio_id,
              numero: Number(fila.numero),
              tipo: fila.tipo,
              salones: Number(fila.salones),
            }
          : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe ese número de piso en el edificio');
        throw error;
      }
    },

    async eliminarPiso(id) {
      try {
        const resultado = await pool.query('DELETE FROM piso WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('El piso tiene salones u horarios asociados');
        }
        throw error;
      }
    },

    async crearSalon(datos) {
      try {
        const resultado = await pool.query(
          `INSERT INTO salon (piso_id, codigo, tipo, capacidad) VALUES ($1, $2, $3, $4)
           RETURNING id, piso_id, codigo, tipo, capacidad`,
          [datos.pisoId, datos.codigo, datos.tipo, datos.capacidad],
        );
        const fila = resultado.rows[0]!;
        return {
          id: fila.id,
          pisoId: fila.piso_id,
          codigo: fila.codigo,
          tipo: fila.tipo,
          capacidad: Number(fila.capacidad),
        };
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un salón con ese código');
        if (esConflictoDeIntegridad(error)) throw errores.datosInvalidos('El piso no existe');
        throw error;
      }
    },

    async actualizarSalon(id, datos) {
      try {
        const resultado = await pool.query(
          `UPDATE salon SET
             codigo = COALESCE($2, codigo),
             tipo = COALESCE($3, tipo),
             capacidad = COALESCE($4, capacidad)
           WHERE id = $1
           RETURNING id, piso_id, codigo, tipo, capacidad`,
          [id, datos.codigo ?? null, datos.tipo ?? null, datos.capacidad ?? null],
        );
        const fila = resultado.rows[0];
        return fila
          ? {
              id: fila.id,
              pisoId: fila.piso_id,
              codigo: fila.codigo,
              tipo: fila.tipo,
              capacidad: Number(fila.capacidad),
            }
          : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un salón con ese código');
        throw error;
      }
    },

    async eliminarSalon(id) {
      try {
        const resultado = await pool.query('DELETE FROM salon WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('El salón tiene horarios asociados');
        }
        throw error;
      }
    },

    async listarHorarios(filtros) {
      const condiciones: string[] = [];
      const valores: unknown[] = [];
      if (filtros.grupoId) {
        valores.push(filtros.grupoId);
        condiciones.push(`h.grupo_id = $${valores.length}`);
      }
      if (filtros.salonId) {
        valores.push(filtros.salonId);
        condiciones.push(`h.salon_id = $${valores.length}`);
      }
      const resultado = await pool.query(
        `${CONSULTA_HORARIO}
         ${condiciones.length > 0 ? `WHERE ${condiciones.join(' AND ')}` : ''}
         ORDER BY p.codigo DESC, asg.nombre, h.dia_semana, h.hora_inicio`,
        valores,
      );
      return resultado.rows.map(filaHorario);
    },

    async crearHorario(datos) {
      try {
        const resultado = await pool.query(
          `INSERT INTO horario (grupo_id, salon_id, dia_semana, hora_inicio, hora_fin)
           VALUES ($1, $2, $3, $4, $5) RETURNING id`,
          [datos.grupoId, datos.salonId, datos.diaSemana, datos.horaInicio, datos.horaFin],
        );
        const id = resultado.rows[0]?.id;
        if (!id) return null;
        const horario = await pool.query(`${CONSULTA_HORARIO} WHERE h.id = $1`, [id]);
        return horario.rows[0] ? filaHorario(horario.rows[0]) : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('El grupo ya tiene clase en ese día y hora');
        if (esConflictoDeIntegridad(error)) {
          throw errores.datosInvalidos('El grupo o el salón no existen');
        }
        throw error;
      }
    },

    async actualizarHorario(id, datos) {
      try {
        const resultado = await pool.query(
          `UPDATE horario SET
             salon_id = COALESCE($2, salon_id),
             dia_semana = COALESCE($3, dia_semana),
             hora_inicio = COALESCE($4, hora_inicio),
             hora_fin = COALESCE($5, hora_fin)
           WHERE id = $1 RETURNING id`,
          [
            id,
            datos.salonId ?? null,
            datos.diaSemana ?? null,
            datos.horaInicio ?? null,
            datos.horaFin ?? null,
          ],
        );
        if (!resultado.rows[0]) return null;
        const horario = await pool.query(`${CONSULTA_HORARIO} WHERE h.id = $1`, [id]);
        return horario.rows[0] ? filaHorario(horario.rows[0]) : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('El grupo ya tiene clase en ese día y hora');
        if (esConflictoDeIntegridad(error)) throw errores.datosInvalidos('El salón indicado no existe');
        throw error;
      }
    },

    async eliminarHorario(id) {
      const resultado = await pool.query('DELETE FROM horario WHERE id = $1', [id]);
      return (resultado.rowCount ?? 0) > 0;
    },
  };
}

const esHora = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'La hora debe ser HH:MM');

const esquemaEdificio = z
  .object({
    codigo: z.string().trim().min(1).max(10),
    nombre: z.string().trim().min(3).max(80),
    sede: z.enum(['CALLE_80']),
  })
  .strict();

const esquemaEdificioParcial = esquemaEdificio.partial().strict();

const esquemaPiso = z
  .object({
    edificioId: z.string().uuid(),
    numero: z.number().int().min(1).max(30),
    tipo: z.enum(['ESTUDIANTIL', 'ADMINISTRATIVO']),
  })
  .strict();

const esquemaPisoParcial = z
  .object({
    numero: z.number().int().min(1).max(30).optional(),
    tipo: z.enum(['ESTUDIANTIL', 'ADMINISTRATIVO']).optional(),
  })
  .strict();

const esquemaSalon = z
  .object({
    pisoId: z.string().uuid(),
    codigo: z.string().trim().min(2).max(10),
    tipo: z.enum(['AULA', 'LABORATORIO', 'OFICINA']),
    capacidad: z.number().int().min(1).max(500),
  })
  .strict();

const esquemaSalonParcial = z
  .object({
    codigo: z.string().trim().min(2).max(10).optional(),
    tipo: z.enum(['AULA', 'LABORATORIO', 'OFICINA']).optional(),
    capacidad: z.number().int().min(1).max(500).optional(),
  })
  .strict();

const esquemaHorario = z
  .object({
    grupoId: z.string().uuid(),
    salonId: z.string().uuid(),
    diaSemana: z.number().int().min(1).max(7),
    horaInicio: esHora,
    horaFin: esHora,
  })
  .strict();

const esquemaHorarioParcial = z
  .object({
    salonId: z.string().uuid().optional(),
    diaSemana: z.number().int().min(1).max(7).optional(),
    horaInicio: esHora.optional(),
    horaFin: esHora.optional(),
  })
  .strict();

const esquemaFiltros = z
  .object({ grupoId: z.string().uuid().optional(), salonId: z.string().uuid().optional() })
  .strict();

const idParam = z.object({ id: z.string().uuid() });

/** Rutas del catálogo de espacios y asignación de salones (Fase 5). */
export function registrarRutasAdminEspacios(
  app: FastifyInstance,
  repo: RepositorioAdminEspacios,
): void {
  const soloAdminEspacios = [app.autenticar, app.requerirRoles('ADMIN_ESPACIOS')];
  const lectura = [app.autenticar, app.requerirRoles('ADMIN_ACADEMICO', 'ADMIN_ESPACIOS')];

  // ── Edificios ───────────────────────────────────────────────────────────
  app.post('/api/v1/espacios/edificios', { preHandler: soloAdminEspacios }, async (peticion, respuesta) => {
    const datos = esquemaEdificio.parse(peticion.body ?? {});
    return respuesta.code(201).send(await repo.crearEdificio(datos));
  });

  app.put('/api/v1/espacios/edificios/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaEdificioParcial.parse(peticion.body ?? {});
    const edificio = await repo.actualizarEdificio(id, datos);
    if (!edificio) throw errores.noEncontrado('El edificio no existe');
    return edificio;
  });

  app.delete('/api/v1/espacios/edificios/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarEdificio(id))) throw errores.noEncontrado('El edificio no existe');
    return { eliminado: id };
  });

  // ── Pisos ───────────────────────────────────────────────────────────────
  app.post('/api/v1/espacios/pisos', { preHandler: soloAdminEspacios }, async (peticion, respuesta) => {
    const datos = esquemaPiso.parse(peticion.body ?? {});
    const piso = await repo.crearPiso(datos);
    if (!piso) throw errores.datosInvalidos('No se pudo crear el piso');
    return respuesta.code(201).send(piso);
  });

  app.put('/api/v1/espacios/pisos/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaPisoParcial.parse(peticion.body ?? {});
    const piso = await repo.actualizarPiso(id, datos);
    if (!piso) throw errores.noEncontrado('El piso no existe');
    return piso;
  });

  app.delete('/api/v1/espacios/pisos/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarPiso(id))) throw errores.noEncontrado('El piso no existe');
    return { eliminado: id };
  });

  // ── Salones ─────────────────────────────────────────────────────────────
  app.post('/api/v1/espacios/salones', { preHandler: soloAdminEspacios }, async (peticion, respuesta) => {
    const datos = esquemaSalon.parse(peticion.body ?? {});
    const salon = await repo.crearSalon(datos);
    if (!salon) throw errores.datosInvalidos('No se pudo crear el salón');
    return respuesta.code(201).send(salon);
  });

  app.put('/api/v1/espacios/salones/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaSalonParcial.parse(peticion.body ?? {});
    const salon = await repo.actualizarSalon(id, datos);
    if (!salon) throw errores.noEncontrado('El salón no existe');
    return salon;
  });

  app.delete('/api/v1/espacios/salones/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarSalon(id))) throw errores.noEncontrado('El salón no existe');
    return { eliminado: id };
  });

  // ── Asignación de salones a horarios ────────────────────────────────────
  app.get('/api/v1/horarios', { preHandler: lectura }, async (peticion) => {
    const filtros = esquemaFiltros.parse(peticion.query ?? {});
    return repo.listarHorarios({
      ...(filtros.grupoId ? { grupoId: filtros.grupoId } : {}),
      ...(filtros.salonId ? { salonId: filtros.salonId } : {}),
    });
  });

  app.post('/api/v1/horarios', { preHandler: soloAdminEspacios }, async (peticion, respuesta) => {
    const datos = esquemaHorario.parse(peticion.body ?? {});
    const horario = await repo.crearHorario(datos);
    if (!horario) throw errores.datosInvalidos('No se pudo crear el horario');
    return respuesta.code(201).send(horario);
  });

  app.put('/api/v1/horarios/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaHorarioParcial.parse(peticion.body ?? {});
    const horario = await repo.actualizarHorario(id, datos);
    if (!horario) throw errores.noEncontrado('El horario no existe');
    return horario;
  });

  app.delete('/api/v1/horarios/:id', { preHandler: soloAdminEspacios }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarHorario(id))) throw errores.noEncontrado('El horario no existe');
    return { eliminado: id };
  });
}
