import { Pool } from 'pg';

/** Crea el pool de conexiones a CockroachDB (§3.2). */
export function crearPool(cadenaConexion: string): Pool {
  return new Pool({
    connectionString: cadenaConexion,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    application_name: 'campus-api',
  });
}

/** Comprueba que la base responde (usado por `/health`). */
export async function verificarBaseDeDatos(pool: Pool): Promise<boolean> {
  try {
    await pool.query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}

/** Cierra el pool en el apagado ordenado del servidor. */
export async function cerrarPool(pool: Pool): Promise<void> {
  await pool.end();
}
