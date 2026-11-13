import cors, { type OriginFunction } from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import { origenesCors, type Env } from './config/env.js';
import { cerrarPool, crearPool, verificarBaseDeDatos } from './db/pool.js';
import { crearClienteS3, verificarBucket } from './lib/s3.js';
import { registrarRutasSalud, type ChequeosSalud } from './modules/health/routes.js';
import { crearRepositorioPerfil, registrarRutasPerfil, type RepositorioPerfil } from './modules/academico/perfil.js';
import { crearRepositorioCarnet, type RepositorioCarnet } from './modules/carnet/carnet.js';
import { registrarRutasCarnet } from './modules/carnet/routes.js';
import {
  crearRepositorioAcceso,
  registrarRutasAcceso,
  type RepositorioAcceso,
} from './modules/acceso/acceso.js';
import { FirmanteCarnet } from './lib/pki.js';
import { leerClaveInstitucional } from './config/institution_keys.js';
import {
  crearRepositorioReservaciones,
  registrarRutasReservaciones,
  type RepositorioReservaciones,
} from './modules/reservaciones/reservaciones.js';
import { crearRepositorioAulas, registrarRutasAulas, type RepositorioAulas } from './modules/aulas/aulas.js';
import { crearRepositorioEntregas, registrarRutasEntregas, type RepositorioEntregas } from './modules/actividades/entregas.js';
import { crearRepositorioCuestionarios, registrarRutasCuestionarios, type RepositorioCuestionarios } from './modules/actividades/cuestionarios.js';
import { crearRepositorioArchivos, registrarRutasArchivos, type RepositorioArchivos } from './modules/archivos/archivos.js';
import { crearVerificador, type TokenVerifier } from './modules/auth/verifier.js';
import { registrarPluginAuth } from './plugins/auth.js';
import { registrarManejadorErrores } from './lib/errors.js';

export interface OpcionesApp {
  env: Env;
  /** Permite inyectar un verificador distinto (pruebas). */
  verificador?: TokenVerifier;
  /** Permite inyectar comprobaciones de salud (pruebas). */
  chequeos?: ChequeosSalud;
  /** Permite inyectar el repositorio de perfil (pruebas). */
  repositorioPerfil?: RepositorioPerfil;
  /** Permite inyectar el repositorio de carnet (pruebas). */
  repositorioCarnet?: RepositorioCarnet;
  /** Permite inyectar el repositorio de acceso/auditoría (pruebas). */
  repositorioAcceso?: RepositorioAcceso;
  /** Permite inyectar el repositorio de reservaciones (pruebas). */
  repositorioReservaciones?: RepositorioReservaciones;
  /** Permite inyectar el repositorio de aulas (pruebas). */
  repositorioAulas?: RepositorioAulas;
  /** Permite inyectar el repositorio de entregas (pruebas). */
  repositorioEntregas?: RepositorioEntregas;
  /** Permite inyectar cuestionarios y archivos (pruebas). */
  repositorioCuestionarios?: RepositorioCuestionarios;
  repositorioArchivos?: RepositorioArchivos;
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

  // Muchos clientes envían `Content-Type: application/json` sin cuerpo (POST/DELETE sin datos).
  // Se interpreta un cuerpo vacío como `{}` en lugar de devolver 400 (D-64).
  app.addContentTypeParser(
    'application/json',
    { parseAs: 'string' },
    (_peticion, cuerpo, listo) => {
      const texto = typeof cuerpo === 'string' ? cuerpo.trim() : '';
      if (texto.length === 0) {
        listo(null, {});
        return;
      }
      try {
        listo(null, JSON.parse(texto));
      } catch {
        listo(new Error('El cuerpo no es un JSON válido'), undefined);
      }
    },
  );

  const origenesPermitidos = origenesCors(env);
  // En desarrollo, Flutter Web elige un puerto aleatorio en cada ejecución: se acepta cualquier
  // puerto de localhost/127.0.0.1, además de la lista configurada (D-63).
  const origenCors: string[] | OriginFunction = env.ENTORNO === 'dev'
    ? (origen, callback) => {
        if (!origen) return callback(null, true);
        if (origenesPermitidos.includes(origen)) return callback(null, true);
        try {
          const url = new URL(origen);
          const esLocal = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
          if (esLocal && (url.protocol === 'http:' || url.protocol === 'https:')) {
            return callback(null, true);
          }
        } catch {
          // Origen con formato inválido: se rechaza abajo.
        }
        return callback(null, false);
      }
    : origenesPermitidos;

  await app.register(cors, {
    origin: origenCors,
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
  registrarRutasPerfil(app, opciones.repositorioPerfil ?? crearRepositorioPerfil(pool));

  // Carnet: si no hay clave institucional configurada, las rutas se omiten (Fase 0/1) y se avisa.
  let repositorioCarnet = opciones.repositorioCarnet;
  if (!repositorioCarnet) {
    try {
      const firmante = await FirmanteCarnet.crear(leerClaveInstitucional(env));
      repositorioCarnet = crearRepositorioCarnet(pool, firmante);
    } catch (error) {
      app.log.warn(
        { err: error },
        'Clave institucional no configurada: las rutas de carnet quedan deshabilitadas',
      );
    }
  }
  if (repositorioCarnet) {
    registrarRutasCarnet(app, repositorioCarnet);
  }
  registrarRutasAcceso(app, opciones.repositorioAcceso ?? crearRepositorioAcceso(pool));
  registrarRutasReservaciones(
    app,
    opciones.repositorioReservaciones ?? crearRepositorioReservaciones(pool),
  );
  registrarRutasAulas(app, opciones.repositorioAulas ?? crearRepositorioAulas(pool));
  registrarRutasEntregas(app, opciones.repositorioEntregas ?? crearRepositorioEntregas(pool, env));
  registrarRutasCuestionarios(
    app,
    opciones.repositorioCuestionarios ?? crearRepositorioCuestionarios(pool),
  );
  if (clienteS3) {
    registrarRutasArchivos(app, opciones.repositorioArchivos ?? crearRepositorioArchivos(pool), clienteS3, env);
  }

  // Ruta mínima autenticada para verificar la cadena de token (Fase 0).
  app.get(
    '/api/v1/sesion',
    { preHandler: app.autenticar },
    async (peticion) => ({ uid: peticion.actor?.uid ?? null, roles: peticion.actor?.roles ?? [] }),
  );

  return app;
}
