import type { Pool, PoolClient } from 'pg';

/**
 * CockroachDB usa SERIALIZABLE por defecto y puede devolver SQLSTATE `40001`
 * (reintento de serialización). Toda escritura transaccional pasa por `withTx`,
 * que reintenta hasta 3 veces con espera exponencial 50/100/200 ms (D-14, §3.2).
 */
export interface OpcionesTx {
  intentosMaximos?: number;
  esperaBaseMs?: number;
  /** Inyectable para pruebas: evita esperas reales. */
  dormir?: (ms: number) => Promise<void>;
}

const esperarDeVerdad = (ms: number) => new Promise<void>((resolver) => setTimeout(resolver, ms));

/** `true` si el error justifica reintentar la transacción completa. */
export function esReintentable(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  return (error as { code?: unknown }).code === '40001';
}

/**
 * Ejecuta `fn` dentro de una transacción y reintenta si CockroachDB pide reintento.
 * La conexión se libera siempre; en caso de reintento se usa una conexión nueva.
 */
export async function withTx<T>(
  pool: Pool,
  fn: (cliente: PoolClient) => Promise<T>,
  opciones: OpcionesTx = {},
): Promise<T> {
  const intentosMaximos = Math.max(1, opciones.intentosMaximos ?? 3);
  const esperaBaseMs = opciones.esperaBaseMs ?? 50;
  const dormir = opciones.dormir ?? esperarDeVerdad;

  let ultimoError: unknown;

  for (let intento = 1; intento <= intentosMaximos; intento += 1) {
    const cliente = await pool.connect();
    try {
      await cliente.query('BEGIN');
      const resultado = await fn(cliente);
      await cliente.query('COMMIT');
      return resultado;
    } catch (error) {
      ultimoError = error;
      try {
        await cliente.query('ROLLBACK');
      } catch {
        // La conexión puede estar rota: se descarta al liberarla y se reintenta con otra.
      }

      if (esReintentable(error) && intento < intentosMaximos) {
        await dormir(esperaBaseMs * 2 ** (intento - 1));
        continue;
      }
      throw error;
    } finally {
      cliente.release();
    }
  }

  throw ultimoError instanceof Error
    ? ultimoError
    : new Error('La transacción agotó los intentos sin un error capturado');
}
