import 'dotenv/config';
import { cargarEnv } from '../config/env.js';
import { ejecutarMigraciones } from './migrate.js';

const env = cargarEnv();
await ejecutarMigraciones({ databaseUrl: env.DATABASE_URL });
console.log('Migraciones aplicadas correctamente.');
