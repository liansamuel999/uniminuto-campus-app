import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import { origenesCors, type Env } from './config/env.js';
import { cerrarPool, crearPool, verificarBaseDeDatos } from './db/pool.js';
import { crearClienteS3, verificarBucket } from './lib/s3.js';
import { registrarRutasSalud, type ChequeosSalud } from './modules/health/routes.js';
import { crearVerificador, type TokenVerifier } from './modules/auth/verifier.js';
import { registrarPluginAuth } from './plugins/auth.js';
import { registrarManejadorErrores } from './lib/errors.js';

export interface OpcionesApp {
  env: Env;
  /** Permite inyectar un verificador distinto (pruebas). */
  verificador?: TokenVerifier;
  /** Permite inyectar comprobaciones de salud (pruebas). */
  chequeos?: ChequeosSalud;
  logger?: boolean;
}

/**
 * Construye la aplicación Fastify sin escuchar en un puerto (testeable con `app.inject`).
 * Módulos de dominio se registran a partir de la Fase 1.
 */
export async function construirApp(opciones: OpcionesApp): Promise<FastifyInstance> {
  const { env } = opciones;

  const app = Fastify({
    logger:
      opciones.logger === false
        ? false
        : {
            level: env.LOG_LEVEL,
            redact: {
              paths: ['req.headers.authorization', 'req.headers.cookie'],
              censor: '[REDACTADO]',
            },
          },
  });

  registrarManejadorErrores(app);

  await app.register(cors, {
    origin: origenesCors(env),
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: false,
  });

  registrarPluginAuth(app, opciones.verificador ?? (await crearVerificador(env)));

  const pool = crearPool(env.DATABASE_URL);
  const clienteS3 = crearClienteS3(env);

  app.addHook('onClose', async () => {
    await cerrarPool(pool);
  });

  const chequeos: ChequeosSalud = opciones.chequeos ?? {
    baseDeDatos: () => verificarBaseDeDatos(pool),
    ...(clienteS3 ? { almacenamiento: () => verificarBucket(clienteS3, env.S3_BUCKET) } : {}),
  };
  registrarRutasSalud(app, chequeos);

  // Ruta mínima autenticada para verificar la cadena de token (Fase 0).
  app.get(
    '/api/v1/sesion',
    { preHandler: app.autenticar },
    async (peticion) => ({ uid: peticion.actor?.uid ?? null, roles: peticion.actor?.roles ?? [] }),
  );

  return app;
}
