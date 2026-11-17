import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { withTx } from '../../db/tx.js';
import { errores } from '../../lib/errors.js';

export interface Periodo {
  id: string;
  codigo: string;
  tipo: string;
  fechaInicio: string;
  fechaFin: string;
  activo: boolean;
}

export interface Asignatura {
  id: string;
  codigo: string;
  nombre: string;
  creditos: number;
}

export interface Grupo {
  id: string;
  asignaturaId: string;
  asignatura: string;
  codigoAsignatura: string;
  /** Código único del curso (NRC o equivalente): es lo que se muestra. */
  codigoCurso: string;
  periodoId: string;
  periodo: string;
  docenteId: string | null;
  docente: string | null;
  /** Detalle interno heredado; no se muestra al usuario. */
  numeroGrupo: string;
  estudiantes: number;
}

export interface Inscripcion {
  id: string;
  estudianteId: string;
  estudiante: string;
  grupoId: string;
  asignatura: string;
  grupo: string;
  periodo: string;
  estado: string;
}

export interface UsuarioAdmin {
  id: string;
  nombres: string;
  apellidos: string;
  correo: string;
  documento: string | null;
  codigoInstitucional: string | null;
  roles: string[];
  programa: string | null;
}

export interface RepositorioAdminAcademico {
  listarPeriodos(): Promise<Periodo[]>;
  crearPeriodo(datos: Omit<Periodo, 'id'>): Promise<Periodo>;
  actualizarPeriodo(id: string, datos: Partial<Omit<Periodo, 'id'>>): Promise<Periodo | null>;
  eliminarPeriodo(id: string): Promise<boolean>;
  listarAsignaturas(): Promise<Asignatura[]>;
  crearAsignatura(datos: Omit<Asignatura, 'id'>): Promise<Asignatura>;
  actualizarAsignatura(id: string, datos: Partial<Omit<Asignatura, 'id'>>): Promise<Asignatura | null>;
  eliminarAsignatura(id: string): Promise<boolean>;
  listarGrupos(
    uidFirebase: string,
    esAdmin: boolean,
    filtros: { periodoId?: string; asignaturaId?: string },
  ): Promise<Grupo[]>;
  crearGrupo(datos: {
    asignaturaId: string;
    periodoId: string;
    codigoCurso: string;
    docenteId?: string | null;
  }): Promise<Grupo | null>;
  actualizarGrupo(
    uidActor: string,
    id: string,
    datos: { codigoCurso?: string; docenteId?: string | null },
  ): Promise<Grupo | null>;
  eliminarGrupo(id: string): Promise<boolean>;
  listarInscripciones(filtros: { grupoId?: string; periodoId?: string }): Promise<Inscripcion[]>;
  crearInscripcion(datos: { estudianteId: string; grupoId: string }): Promise<Inscripcion | null>;
  actualizarInscripcion(id: string, estado: string): Promise<Inscripcion | null>;
  eliminarInscripcion(id: string): Promise<boolean>;
  listarUsuarios(filtros: { rol?: string }): Promise<UsuarioAdmin[]>;
}

const isoFecha = (valor: string | Date) =>
  (valor instanceof Date ? valor : new Date(valor)).toISOString().slice(0, 10);

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

async function registrarAuditoria(
  cliente: { query: Pool['query'] },
  uidActor: string,
  accion: string,
  recurso: string,
): Promise<void> {
  await cliente.query(
    `INSERT INTO evento_auditoria (actor_id, accion, recurso, resultado)
     VALUES ((SELECT id FROM usuario WHERE uid_firebase = $1), $2, $3, 'OK')`,
    [uidActor, accion, recurso],
  );
}

const CONSULTA_GRUPO = `
  SELECT g.id, g.asignatura_id, asg.nombre AS asignatura, asg.codigo AS codigo_asignatura,
         g.codigo_curso, g.periodo_id, p.codigo AS periodo, g.docente_id,
         d.nombres || ' ' || d.apellidos AS docente, g.numero_grupo,
         (SELECT COUNT(*)::int FROM inscripcion i
          WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS estudiantes
  FROM grupo g
  JOIN asignatura asg ON asg.id = g.asignatura_id
  JOIN periodo p ON p.id = g.periodo_id
  LEFT JOIN usuario d ON d.id = g.docente_id
`;

const CONSULTA_INSCRIPCION = `
  SELECT i.id, i.estudiante_id, e.nombres || ' ' || e.apellidos AS estudiante,
         i.grupo_id, asg.nombre AS asignatura, g.codigo_curso AS grupo,
         p.codigo AS periodo, i.estado
  FROM inscripcion i
  JOIN usuario e ON e.id = i.estudiante_id
  JOIN grupo g ON g.id = i.grupo_id
  JOIN asignatura asg ON asg.id = g.asignatura_id
  JOIN periodo p ON p.id = g.periodo_id
`;

/** CRUD administrativo del módulo académico (matriz §5, Fase 5). */
export function crearRepositorioAdminAcademico(pool: Pool): RepositorioAdminAcademico {
  const filaPeriodo = (fila: {
    id: string;
    codigo: string;
    tipo: string;
    fecha_inicio: string | Date;
    fecha_fin: string | Date;
    activo: boolean;
  }): Periodo => ({
    id: fila.id,
    codigo: fila.codigo,
    tipo: fila.tipo,
    fechaInicio: isoFecha(fila.fecha_inicio),
    fechaFin: isoFecha(fila.fecha_fin),
    activo: fila.activo,
  });

  const filaGrupo = (fila: {
    id: string;
    asignatura_id: string;
    asignatura: string;
    codigo_asignatura: string;
    codigo_curso: string;
    periodo_id: string;
    periodo: string;
    docente_id: string | null;
    docente: string | null;
    numero_grupo: string;
    estudiantes: string;
  }): Grupo => ({
    id: fila.id,
    asignaturaId: fila.asignatura_id,
    asignatura: fila.asignatura,
    codigoAsignatura: fila.codigo_asignatura,
    codigoCurso: fila.codigo_curso,
    periodoId: fila.periodo_id,
    periodo: fila.periodo,
    docenteId: fila.docente_id,
    docente: fila.docente,
    numeroGrupo: fila.numero_grupo,
    estudiantes: Number(fila.estudiantes),
  });

  const filaInscripcion = (fila: {
    id: string;
    estudiante_id: string;
    estudiante: string;
    grupo_id: string;
    asignatura: string;
    grupo: string;
    periodo: string;
    estado: string;
  }): Inscripcion => ({
    id: fila.id,
    estudianteId: fila.estudiante_id,
    estudiante: fila.estudiante,
    grupoId: fila.grupo_id,
    asignatura: fila.asignatura,
    grupo: fila.grupo,
    periodo: fila.periodo,
    estado: fila.estado,
  });

  return {
    async listarPeriodos() {
      const resultado = await pool.query(
        `SELECT id, codigo, tipo, fecha_inicio, fecha_fin, activo
         FROM periodo ORDER BY fecha_inicio DESC`,
      );
      return resultado.rows.map(filaPeriodo);
    },

    async crearPeriodo(datos) {
      try {
        return await withTx(pool, async (cliente) => {
          if (datos.activo) {
            await cliente.query('UPDATE periodo SET activo = false WHERE activo');
          }
          const resultado = await cliente.query(
            `INSERT INTO periodo (codigo, tipo, fecha_inicio, fecha_fin, activo)
             VALUES ($1, $2, $3, $4, $5)
             RETURNING id, codigo, tipo, fecha_inicio, fecha_fin, activo`,
            [datos.codigo, datos.tipo, datos.fechaInicio, datos.fechaFin, datos.activo],
          );
          return filaPeriodo(resultado.rows[0]!);
        });
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un periodo con ese código');
        throw error;
      }
    },

    async actualizarPeriodo(id, datos) {
      try {
        return await withTx(pool, async (cliente) => {
          if (datos.activo === true) {
            await cliente.query('UPDATE periodo SET activo = false WHERE activo AND id <> $1', [id]);
          }
          const resultado = await cliente.query(
            `UPDATE periodo SET
               codigo = COALESCE($2, codigo),
               tipo = COALESCE($3, tipo),
               fecha_inicio = COALESCE($4, fecha_inicio),
               fecha_fin = COALESCE($5, fecha_fin),
               activo = COALESCE($6, activo)
             WHERE id = $1
             RETURNING id, codigo, tipo, fecha_inicio, fecha_fin, activo`,
            [
              id,
              datos.codigo ?? null,
              datos.tipo ?? null,
              datos.fechaInicio ?? null,
              datos.fechaFin ?? null,
              datos.activo ?? null,
            ],
          );
          return resultado.rows[0] ? filaPeriodo(resultado.rows[0]) : null;
        });
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un periodo con ese código');
        throw error;
      }
    },

    async eliminarPeriodo(id) {
      try {
        const resultado = await pool.query('DELETE FROM periodo WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('El periodo tiene grupos u otros registros asociados');
        }
        throw error;
      }
    },

    async listarAsignaturas() {
      const resultado = await pool.query(
        'SELECT id, codigo, nombre, creditos FROM asignatura ORDER BY nombre',
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        codigo: fila.codigo,
        nombre: fila.nombre,
        creditos: Number(fila.creditos),
      }));
    },

    async crearAsignatura(datos) {
      try {
        const resultado = await pool.query(
          `INSERT INTO asignatura (codigo, nombre, creditos) VALUES ($1, $2, $3)
           RETURNING id, codigo, nombre, creditos`,
          [datos.codigo, datos.nombre, datos.creditos],
        );
        const fila = resultado.rows[0]!;
        return { id: fila.id, codigo: fila.codigo, nombre: fila.nombre, creditos: Number(fila.creditos) };
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe una asignatura con ese código');
        throw error;
      }
    },

    async actualizarAsignatura(id, datos) {
      try {
        const resultado = await pool.query(
          `UPDATE asignatura SET
             codigo = COALESCE($2, codigo),
             nombre = COALESCE($3, nombre),
             creditos = COALESCE($4, creditos)
           WHERE id = $1
           RETURNING id, codigo, nombre, creditos`,
          [id, datos.codigo ?? null, datos.nombre ?? null, datos.creditos ?? null],
        );
        const fila = resultado.rows[0];
        return fila ? { id: fila.id, codigo: fila.codigo, nombre: fila.nombre, creditos: Number(fila.creditos) } : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe una asignatura con ese código');
        throw error;
      }
    },

    async eliminarAsignatura(id) {
      try {
        const resultado = await pool.query('DELETE FROM asignatura WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('La asignatura tiene grupos u otros registros asociados');
        }
        throw error;
      }
    },

    async listarGrupos(uidFirebase, esAdmin, filtros) {
      const condiciones: string[] = [];
      const valores: unknown[] = [];
      if (!esAdmin) {
        valores.push(uidFirebase);
        condiciones.push(`d.uid_firebase = $${valores.length}`);
      }
      if (filtros.periodoId) {
        valores.push(filtros.periodoId);
        condiciones.push(`g.periodo_id = $${valores.length}`);
      }
      if (filtros.asignaturaId) {
        valores.push(filtros.asignaturaId);
        condiciones.push(`g.asignatura_id = $${valores.length}`);
      }
      const resultado = await pool.query(
        `${CONSULTA_GRUPO}
         ${condiciones.length > 0 ? `WHERE ${condiciones.join(' AND ')}` : ''}
         ORDER BY p.codigo DESC, asg.nombre, g.codigo_curso`,
        valores,
      );
      return resultado.rows.map(filaGrupo);
    },

    async crearGrupo(datos) {
      try {
        const resultado = await pool.query(
          `INSERT INTO grupo (asignatura_id, periodo_id, docente_id, numero_grupo, codigo_curso)
           VALUES ($1, $2, $3, $4, $4) RETURNING id`,
          [datos.asignaturaId, datos.periodoId, datos.docenteId ?? null, datos.codigoCurso],
        );
        const id = resultado.rows[0]?.id;
        if (!id) return null;
        const grupo = await pool.query(`${CONSULTA_GRUPO} WHERE g.id = $1`, [id]);
        return grupo.rows[0] ? filaGrupo(grupo.rows[0]) : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un curso con ese código');
        if (esConflictoDeIntegridad(error)) {
          throw errores.datosInvalidos('La asignatura, el periodo o el docente no existen');
        }
        throw error;
      }
    },

    async actualizarGrupo(uidActor, id, datos) {
      try {
        return await withTx(pool, async (cliente) => {
          const anterior = await cliente.query<{ docente_id: string | null }>(
            'SELECT docente_id FROM grupo WHERE id = $1',
            [id],
          );
          if (!anterior.rows[0]) return null;

          await cliente.query(
            `UPDATE grupo SET
               codigo_curso = COALESCE($2, codigo_curso),
               numero_grupo = COALESCE($2, numero_grupo),
               docente_id = CASE WHEN $3::boolean THEN $4::uuid ELSE docente_id END
             WHERE id = $1`,
            [
              id,
              datos.codigoCurso ?? null,
              datos.docenteId !== undefined,
              datos.docenteId ?? null,
            ],
          );

          if (datos.docenteId !== undefined && datos.docenteId !== anterior.rows[0].docente_id) {
            await registrarAuditoria(cliente, uidActor, 'ASIGNAR_DOCENTE', `grupo:${id}`);
          }

          const grupo = await cliente.query(`${CONSULTA_GRUPO} WHERE g.id = $1`, [id]);
          return grupo.rows[0] ? filaGrupo(grupo.rows[0]) : null;
        });
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('Ya existe un curso con ese código');
        if (esConflictoDeIntegridad(error)) throw errores.datosInvalidos('El docente indicado no existe');
        throw error;
      }
    },

    async eliminarGrupo(id) {
      try {
        const resultado = await pool.query('DELETE FROM grupo WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('El grupo tiene inscripciones, horarios o aulas asociadas');
        }
        throw error;
      }
    },

    async listarInscripciones(filtros) {
      const condiciones: string[] = [];
      const valores: unknown[] = [];
      if (filtros.grupoId) {
        valores.push(filtros.grupoId);
        condiciones.push(`i.grupo_id = $${valores.length}`);
      }
      if (filtros.periodoId) {
        valores.push(filtros.periodoId);
        condiciones.push(`g.periodo_id = $${valores.length}`);
      }
      const resultado = await pool.query(
        `${CONSULTA_INSCRIPCION}
         ${condiciones.length > 0 ? `WHERE ${condiciones.join(' AND ')}` : ''}
         ORDER BY e.apellidos, e.nombres`,
        valores,
      );
      return resultado.rows.map(filaInscripcion);
    },

    async crearInscripcion(datos) {
      const estudiante = await pool.query<{ id: string }>(
        `SELECT u.id FROM usuario u
         JOIN usuario_rol ur ON ur.usuario_id = u.id
         JOIN rol r ON r.id = ur.rol_id
         WHERE u.id = $1 AND r.nombre = 'ESTUDIANTE'`,
        [datos.estudianteId],
      );
      if (!estudiante.rows[0]) throw errores.datosInvalidos('El usuario no existe o no es estudiante');

      try {
        const resultado = await pool.query(
          `INSERT INTO inscripcion (estudiante_id, grupo_id) VALUES ($1, $2) RETURNING id`,
          [datos.estudianteId, datos.grupoId],
        );
        const id = resultado.rows[0]?.id;
        if (!id) return null;
        const inscripcion = await pool.query(`${CONSULTA_INSCRIPCION} WHERE i.id = $1`, [id]);
        return inscripcion.rows[0] ? filaInscripcion(inscripcion.rows[0]) : null;
      } catch (error) {
        if (esDuplicado(error)) throw errores.conflicto('El estudiante ya está inscrito en ese grupo');
        if (esConflictoDeIntegridad(error)) throw errores.datosInvalidos('El grupo indicado no existe');
        throw error;
      }
    },

    async actualizarInscripcion(id, estado) {
      const resultado = await pool.query(
        `UPDATE inscripcion SET estado = $2 WHERE id = $1 RETURNING id`,
        [id, estado],
      );
      if (!resultado.rows[0]) return null;
      const inscripcion = await pool.query(`${CONSULTA_INSCRIPCION} WHERE i.id = $1`, [id]);
      return inscripcion.rows[0] ? filaInscripcion(inscripcion.rows[0]) : null;
    },

    async eliminarInscripcion(id) {
      try {
        const resultado = await pool.query('DELETE FROM inscripcion WHERE id = $1', [id]);
        return (resultado.rowCount ?? 0) > 0;
      } catch (error) {
        if (esConflictoDeIntegridad(error)) {
          throw errores.conflicto('La inscripción tiene entregas, calificaciones o evaluaciones asociadas');
        }
        throw error;
      }
    },

    async listarUsuarios(filtros) {
      const condiciones: string[] = [];
      const valores: unknown[] = [];
      if (filtros.rol) {
        valores.push(filtros.rol);
        condiciones.push(`EXISTS (
          SELECT 1 FROM usuario_rol ur JOIN rol r ON r.id = ur.rol_id
          WHERE ur.usuario_id = u.id AND r.nombre = $${valores.length})`);
      }
      const resultado = await pool.query(
        `SELECT u.id, u.nombres, u.apellidos, u.correo, u.documento, u.codigo_institucional,
                p.nombre AS programa,
                (SELECT COALESCE(array_agg(r.nombre ORDER BY r.nombre), '{}')
                 FROM usuario_rol ur JOIN rol r ON r.id = ur.rol_id
                 WHERE ur.usuario_id = u.id) AS roles
         FROM usuario u LEFT JOIN programa p ON p.id = u.programa_id
         ${condiciones.length > 0 ? `WHERE ${condiciones.join(' AND ')}` : ''}
         ORDER BY u.apellidos, u.nombres`,
        valores,
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        nombres: fila.nombres,
        apellidos: fila.apellidos,
        correo: fila.correo,
        documento: fila.documento,
        codigoInstitucional: fila.codigo_institucional,
        roles: (fila.roles as string[] | null) ?? [],
        programa: fila.programa,
      }));
    },
  };
}

const esFecha = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'La fecha debe ser YYYY-MM-DD');

const esquemaPeriodo = z
  .object({
    codigo: z.string().trim().regex(/^\d{4}-\d$/, 'El código debe ser AAAA-N'),
    tipo: z.enum(['SEMESTRAL', 'CUATRIMESTRAL']),
    fechaInicio: esFecha,
    fechaFin: esFecha,
    activo: z.boolean(),
  })
  .strict();

const esquemaPeriodoParcial = esquemaPeriodo.partial().strict();

const esquemaAsignatura = z
  .object({
    codigo: z.string().trim().min(2).max(20),
    nombre: z.string().trim().min(3).max(120),
    creditos: z.number().int().min(1).max(10),
  })
  .strict();

const esquemaAsignaturaParcial = esquemaAsignatura.partial().strict();

const esquemaGrupo = z
  .object({
    asignaturaId: z.string().uuid(),
    periodoId: z.string().uuid(),
    codigoCurso: z
      .string()
      .trim()
      .min(3)
      .max(20)
      .regex(/^[A-Za-z0-9-]+$/, 'Usa letras, números o guiones'),
    docenteId: z.string().uuid().nullable().optional(),
  })
  .strict();

const esquemaGrupoParcial = z
  .object({
    codigoCurso: z
      .string()
      .trim()
      .min(3)
      .max(20)
      .regex(/^[A-Za-z0-9-]+$/, 'Usa letras, números o guiones')
      .optional(),
    docenteId: z.string().uuid().nullable().optional(),
  })
  .strict();

const esquemaInscripcion = z
  .object({ estudianteId: z.string().uuid(), grupoId: z.string().uuid() })
  .strict();

const esquemaInscripcionParcial = z
  .object({ estado: z.enum(['ACTIVA', 'RETIRADA', 'APROBADA', 'REPROBADA']) })
  .strict();

const esquemaFiltros = z
  .object({
    periodoId: z.string().uuid().optional(),
    asignaturaId: z.string().uuid().optional(),
    grupoId: z.string().uuid().optional(),
    rol: z.enum(['ESTUDIANTE', 'DOCENTE', 'ADMIN_ACADEMICO', 'ADMIN_ESPACIOS', 'SEGURIDAD', 'SOPORTE', 'AUDITOR']).optional(),
  })
  .strict();

const idParam = z.object({ id: z.string().uuid() });

/** Rutas de administración académica (Fase 5): periodos, asignaturas, grupos e inscripciones. */
export function registrarRutasAdminAcademico(
  app: FastifyInstance,
  repo: RepositorioAdminAcademico,
): void {
  const soloAdminAcademico = [app.autenticar, app.requerirRoles('ADMIN_ACADEMICO')];
  const lecturaAcademica = [app.autenticar, app.requerirRoles('DOCENTE', 'ADMIN_ACADEMICO')];

  // ── Periodos ────────────────────────────────────────────────────────────
  app.get('/api/v1/periodos', { preHandler: lecturaAcademica }, async () => repo.listarPeriodos());

  app.post('/api/v1/periodos', { preHandler: soloAdminAcademico }, async (peticion, respuesta) => {
    const datos = esquemaPeriodo.parse(peticion.body ?? {});
    return respuesta.code(201).send(await repo.crearPeriodo(datos));
  });

  app.put('/api/v1/periodos/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaPeriodoParcial.parse(peticion.body ?? {});
    const periodo = await repo.actualizarPeriodo(id, datos);
    if (!periodo) throw errores.noEncontrado('El periodo no existe');
    return periodo;
  });

  app.delete('/api/v1/periodos/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarPeriodo(id))) throw errores.noEncontrado('El periodo no existe');
    return { eliminado: id };
  });

  // ── Asignaturas ─────────────────────────────────────────────────────────
  app.get('/api/v1/asignaturas', { preHandler: lecturaAcademica }, async () =>
    repo.listarAsignaturas(),
  );

  app.post('/api/v1/asignaturas', { preHandler: soloAdminAcademico }, async (peticion, respuesta) => {
    const datos = esquemaAsignatura.parse(peticion.body ?? {});
    return respuesta.code(201).send(await repo.crearAsignatura(datos));
  });

  app.put('/api/v1/asignaturas/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaAsignaturaParcial.parse(peticion.body ?? {});
    const asignatura = await repo.actualizarAsignatura(id, datos);
    if (!asignatura) throw errores.noEncontrado('La asignatura no existe');
    return asignatura;
  });

  app.delete('/api/v1/asignaturas/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarAsignatura(id))) throw errores.noEncontrado('La asignatura no existe');
    return { eliminado: id };
  });

  // ── Grupos y asignación de docentes ─────────────────────────────────────
  app.get('/api/v1/grupos', { preHandler: lecturaAcademica }, async (peticion) => {
    const filtros = esquemaFiltros.parse(peticion.query ?? {});
    const esAdmin = peticion.actor?.roles.includes('ADMIN_ACADEMICO') ?? false;
    return repo.listarGrupos(peticion.actor!.uid, esAdmin, {
      ...(filtros.periodoId ? { periodoId: filtros.periodoId } : {}),
      ...(filtros.asignaturaId ? { asignaturaId: filtros.asignaturaId } : {}),
    });
  });

  app.post('/api/v1/grupos', { preHandler: soloAdminAcademico }, async (peticion, respuesta) => {
    const datos = esquemaGrupo.parse(peticion.body ?? {});
    const grupo = await repo.crearGrupo(datos);
    return respuesta.code(201).send(grupo);
  });

  app.put('/api/v1/grupos/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaGrupoParcial.parse(peticion.body ?? {});
    const grupo = await repo.actualizarGrupo(peticion.actor!.uid, id, datos);
    if (!grupo) throw errores.noEncontrado('El grupo no existe');
    return grupo;
  });

  app.delete('/api/v1/grupos/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarGrupo(id))) throw errores.noEncontrado('El grupo no existe');
    return { eliminado: id };
  });

  // ── Inscripciones ───────────────────────────────────────────────────────
  app.get('/api/v1/inscripciones', { preHandler: lecturaAcademica }, async (peticion) => {
    const filtros = esquemaFiltros.parse(peticion.query ?? {});
    return repo.listarInscripciones({
      ...(filtros.grupoId ? { grupoId: filtros.grupoId } : {}),
      ...(filtros.periodoId ? { periodoId: filtros.periodoId } : {}),
    });
  });

  app.post('/api/v1/inscripciones', { preHandler: soloAdminAcademico }, async (peticion, respuesta) => {
    const datos = esquemaInscripcion.parse(peticion.body ?? {});
    const inscripcion = await repo.crearInscripcion(datos);
    return respuesta.code(201).send(inscripcion);
  });

  app.put('/api/v1/inscripciones/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    const datos = esquemaInscripcionParcial.parse(peticion.body ?? {});
    const inscripcion = await repo.actualizarInscripcion(id, datos.estado);
    if (!inscripcion) throw errores.noEncontrado('La inscripción no existe');
    return inscripcion;
  });

  app.delete('/api/v1/inscripciones/:id', { preHandler: soloAdminAcademico }, async (peticion) => {
    const { id } = idParam.parse(peticion.params);
    if (!(await repo.eliminarInscripcion(id))) throw errores.noEncontrado('La inscripción no existe');
    return { eliminado: id };
  });

  // ── Catálogo de usuarios para asignaciones ──────────────────────────────
  app.get('/api/v1/admin/usuarios', { preHandler: soloAdminAcademico }, async (peticion) => {
    const filtros = esquemaFiltros.parse(peticion.query ?? {});
    return repo.listarUsuarios(filtros.rol ? { rol: filtros.rol } : {});
  });
}
