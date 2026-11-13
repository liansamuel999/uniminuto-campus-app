import { cargarEnv, type Env } from '../src/config/env.js';
import type { ChequeosSalud } from '../src/modules/health/routes.js';

export const SECRETO_PRUEBAS = 'secreto-de-pruebas-con-longitud-suficiente';

/** Entorno de desarrollo válido para construir la app en pruebas. */
export function envPruebas(sobrescribir: Record<string, string> = {}): Env {
  return cargarEnv({
    ENTORNO: 'dev',
    DATABASE_URL: 'postgresql://root@localhost:26257/campus?sslmode=disable',
    AUTH_DEV_SECRET: SECRETO_PRUEBAS,
    CORS_ORIGINS: 'http://localhost:5173',
    ...sobrescribir,
  });
}

/** Comprobaciones de salud que responden bien, inyectables para no tocar infraestructura. */
export const CHEQUEOS_OK: ChequeosSalud = {
  baseDeDatos: async () => true,
  almacenamiento: async () => true,
};
