import path from 'node:path';
import { fileURLToPath } from 'node:url';

type RunnerMigraciones = (opciones: Record<string, unknown>) => Promise<unknown>;

const DIRECTORIO_ACTUAL = path.dirname(fileURLToPath(import.meta.url));

/**
 * `infra/migrations` está tres niveles arriba tanto en `src/db/` (tsx) como en `dist/db/` (build),
 * así que la ruta resuelve igual en desarrollo y en producción.
 */
export const DIRECTORIO_MIGRACIONES = path.resolve(DIRECTORIO_ACTUAL, '../../../infra/migrations');

/**
 * node-pg-migrate se publica como CJS y su interop varía entre versiones: se resuelve en runtime
 * aceptando `default`, `default.default` o `runner` (D-09).
 */
async function cargarRunner(): Promise<RunnerMigraciones> {
  const modulo = (await import('node-pg-migrate')) as unknown as Record<string, unknown>;
  const porDefecto = modulo['default'] as Record<string, unknown> | RunnerMigraciones | undefined;
  const candidatos = [
    typeof porDefecto === 'function' ? porDefecto : undefined,
    typeof porDefecto === 'object' && porDefecto !== null
      ? (porDefecto['default'] as RunnerMigraciones | undefined)
      : undefined,
    modulo['runner'] as RunnerMigraciones | undefined,
  ];
  const runner = candidatos.find((candidato): candidato is RunnerMigraciones => typeof candidato === 'function');
  if (!runner) {
    throw new Error('No se pudo cargar el runner de node-pg-migrate');
  }
  return runner;
}

export interface OpcionesMigracion {
  databaseUrl: string;
  direccion?: 'up' | 'down';
  pasos?: number;
  silencioso?: boolean;
}

/** Aplica las migraciones SQL numeradas de `infra/migrations`. */
export async function ejecutarMigraciones(opciones: OpcionesMigracion): Promise<void> {
  const runner = await cargarRunner();
  const registro = opciones.silencioso ? () => {} : undefined;

  await runner({
    databaseUrl: opciones.databaseUrl,
    dir: DIRECTORIO_MIGRACIONES,
    direction: opciones.direccion ?? 'up',
    migrationsTable: 'pgmigrations',
    count: opciones.pasos,
    verbose: !opciones.silencioso,
    log: registro,
    checkOrder: true,
  });
}
