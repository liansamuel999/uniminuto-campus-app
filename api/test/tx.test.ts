import { describe, expect, it } from 'vitest';
import type { Pool, PoolClient } from 'pg';
import { esReintentable, withTx } from '../src/db/tx.js';

interface PoolFalso {
  pool: Pool;
  consultas: string[];
  liberaciones: () => number;
}

/** Pool falso: cada llamada a `SELECT` consume el siguiente comportamiento de la lista. */
function crearPoolFalso(comportamientos: Array<'ok' | 'reintento'>): PoolFalso {
  let indiceComportamiento = 0;
  let liberaciones = 0;
  const consultas: string[] = [];

  const cliente = {
    query: async (sql: string) => {
      consultas.push(sql);
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rows: [] };
      }
      const comportamiento = comportamientos[indiceComportamiento] ?? 'ok';
      indiceComportamiento += 1;
      if (comportamiento === 'reintento') {
        const error = Object.assign(new Error('serialization failure'), { code: '40001' });
        throw error;
      }
      return { rows: [{ ok: 1 }] };
    },
    release: () => {
      liberaciones += 1;
    },
  } as unknown as PoolClient;

  return {
    pool: { connect: async () => cliente } as unknown as Pool,
    consultas,
    liberaciones: () => liberaciones,
  };
}

describe('withTx (reintento por SQLSTATE 40001)', () => {
  it('reintenta y devuelve el resultado cuando el primer intento pide reintento', async () => {
    const falso = crearPoolFalso(['reintento', 'ok']);
    const esperas: number[] = [];

    const resultado = await withTx(
      falso.pool,
      async (cliente) => {
        await cliente.query('SELECT 1');
        return 'hecho';
      },
      { esperaBaseMs: 5, dormir: async (ms) => void esperas.push(ms) },
    );

    expect(resultado).toBe('hecho');
    expect(esperas).toEqual([5]);
    expect(falso.consultas).toEqual(['BEGIN', 'SELECT 1', 'ROLLBACK', 'BEGIN', 'SELECT 1', 'COMMIT']);
    expect(falso.liberaciones()).toBe(2);
  });

  it('aplica espera exponencial entre intentos', async () => {
    const falso = crearPoolFalso(['reintento', 'reintento', 'ok']);
    const esperas: number[] = [];

    await withTx(falso.pool, async (cliente) => cliente.query('SELECT 1'), {
      esperaBaseMs: 5,
      dormir: async (ms) => void esperas.push(ms),
    });

    expect(esperas).toEqual([5, 10]);
  });

  it('propaga el error tras agotar los 3 intentos', async () => {
    const falso = crearPoolFalso(['reintento', 'reintento', 'reintento', 'ok']);
    const esperas: number[] = [];

    await expect(
      withTx(falso.pool, async (cliente) => cliente.query('SELECT 1'), {
        esperaBaseMs: 5,
        dormir: async (ms) => void esperas.push(ms),
      }),
    ).rejects.toMatchObject({ code: '40001' });

    expect(esperas).toEqual([5, 10]);
    expect(falso.liberaciones()).toBe(3);
  });

  it('no reintenta ante un error que no es de serialización', async () => {
    const falso = crearPoolFalso(['ok']);
    const esperas: number[] = [];
    const errorDeNegocio = Object.assign(new Error('nota fuera de rango'), { code: '23514' });

    await expect(
      withTx(
        falso.pool,
        async () => {
          throw errorDeNegocio;
        },
        { dormir: async (ms) => void esperas.push(ms) },
      ),
    ).rejects.toBe(errorDeNegocio);

    expect(esperas).toEqual([]);
    expect(falso.consultas).toEqual(['BEGIN', 'ROLLBACK']);
  });

  it('identifica correctamente el código reintentable', () => {
    expect(esReintentable({ code: '40001' })).toBe(true);
    expect(esReintentable({ code: '23505' })).toBe(false);
    expect(esReintentable(null)).toBe(false);
    expect(esReintentable('40001')).toBe(false);
  });
});
