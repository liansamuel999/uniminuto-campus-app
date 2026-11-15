import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface EdificioCampus {
  id: string;
  codigo: string;
  nombre: string;
  sede: string;
  pisos: number;
}

export interface PisoCampus {
  id: string;
  numero: number;
  tipo: string;
  salones: number;
}

export interface SalonCampus {
  id: string;
  codigo: string;
  tipo: string;
  capacidad: number;
}

export interface RepositorioEspacios {
  edificios(): Promise<EdificioCampus[]>;
  pisos(edificioId: string): Promise<PisoCampus[] | null>;
  salones(pisoId: string): Promise<SalonCampus[] | null>;
}

/** Jerarquía Edificio → Piso → Salón del campus Calle 80 (§4.3). */
export function crearRepositorioEspacios(pool: Pool): RepositorioEspacios {
  return {
    async edificios() {
      const resultado = await pool.query<{
        id: string;
        codigo: string;
        nombre: string;
        sede: string;
        pisos: string;
      }>(
        `SELECT e.id, e.codigo, e.nombre, e.sede,
                COUNT(p.id)::int AS pisos
         FROM edificio e LEFT JOIN piso p ON p.edificio_id = e.id
         GROUP BY e.id ORDER BY e.codigo`,
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        codigo: fila.codigo,
        nombre: fila.nombre,
        sede: fila.sede,
        pisos: Number(fila.pisos),
      }));
    },

    async pisos(edificioId) {
      const edificio = await pool.query('SELECT 1 FROM edificio WHERE id = $1', [edificioId]);
      if ((edificio.rowCount ?? 0) === 0) return null;

      const resultado = await pool.query<{
        id: string;
        numero: number;
        tipo: string;
        salones: string;
      }>(
        `SELECT p.id, p.numero, p.tipo, COUNT(s.id)::int AS salones
         FROM piso p LEFT JOIN salon s ON s.piso_id = p.id
         WHERE p.edificio_id = $1
         GROUP BY p.id ORDER BY p.numero`,
        [edificioId],
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        numero: Number(fila.numero),
        tipo: fila.tipo,
        salones: Number(fila.salones),
      }));
    },

    async salones(pisoId) {
      const piso = await pool.query('SELECT 1 FROM piso WHERE id = $1', [pisoId]);
      if ((piso.rowCount ?? 0) === 0) return null;

      const resultado = await pool.query<{
        id: string;
        codigo: string;
        tipo: string;
        capacidad: string;
      }>(
        `SELECT id, codigo, tipo, capacidad FROM salon WHERE piso_id = $1 ORDER BY codigo`,
        [pisoId],
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        codigo: fila.codigo,
        tipo: fila.tipo,
        capacidad: Number(fila.capacidad),
      }));
    },
  };
}

const esquemaId = z.object({ id: z.string().uuid() });

/** Rutas de lectura de la jerarquía del campus (§7.7). */
export function registrarRutasEspacios(app: FastifyInstance, repo: RepositorioEspacios): void {
  app.get('/api/v1/espacios/edificios', { preHandler: app.autenticar }, async () => repo.edificios());

  app.get('/api/v1/espacios/edificios/:id/pisos', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = esquemaId.parse(peticion.params);
    const pisos = await repo.pisos(id);
    if (!pisos) throw errores.noEncontrado('El edificio no existe');
    return pisos;
  });

  app.get('/api/v1/espacios/pisos/:id/salones', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = esquemaId.parse(peticion.params);
    const salones = await repo.salones(id);
    if (!salones) throw errores.noEncontrado('El piso no existe');
    return salones;
  });
}
