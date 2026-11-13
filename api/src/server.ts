import 'dotenv/config';
import { construirApp } from './app.js';
import { cargarEnv } from './config/env.js';

const env = cargarEnv();
const app = await construirApp({ env });

const cerrar = async (senal: string) => {
  app.log.info(`Señal ${senal} recibida; cerrando la API`);
  await app.close();
  process.exit(0);
};

process.on('SIGINT', () => void cerrar('SIGINT'));
process.on('SIGTERM', () => void cerrar('SIGTERM'));

try {
  await app.listen({ port: env.PORT, host: '0.0.0.0' });
  app.log.info({ puerto: env.PORT, entorno: env.ENTORNO }, 'API escuchando');
} catch (error) {
  app.log.error({ err: error }, 'No se pudo iniciar la API');
  process.exit(1);
}
