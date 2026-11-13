import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';

/** Catálogo de códigos de error del contrato (D-17). */
export type CodigoError =
  | 'NO_AUTORIZADO'
  | 'PROHIBIDO'
  | 'DATOS_INVALIDOS'
  | 'NO_ENCONTRADO'
  | 'CONFLICTO'
  | 'ERROR_INTERNO'
  | 'SERVICIO_NO_DISPONIBLE';

/** Error de aplicación con código estable y estado HTTP. */
export class AppError extends Error {
  readonly codigo: CodigoError;
  readonly estado: number;

  constructor(codigo: CodigoError, mensaje: string, estado = 400) {
    super(mensaje);
    this.name = 'AppError';
    this.codigo = codigo;
    this.estado = estado;
  }
}

/** Constructores de los errores más usados. */
export const errores = {
  noAutorizado: (mensaje = 'Token ausente o inválido') =>
    new AppError('NO_AUTORIZADO', mensaje, 401),
  prohibido: (mensaje = 'No tienes permiso para esta operación') =>
    new AppError('PROHIBIDO', mensaje, 403),
  datosInvalidos: (mensaje = 'Datos inválidos') => new AppError('DATOS_INVALIDOS', mensaje, 400),
  noEncontrado: (mensaje = 'Recurso no encontrado') => new AppError('NO_ENCONTRADO', mensaje, 404),
  conflicto: (mensaje = 'Conflicto con el estado actual del recurso') =>
    new AppError('CONFLICTO', mensaje, 409),
  interno: (mensaje = 'Error interno del servidor') => new AppError('ERROR_INTERNO', mensaje, 500),
  noDisponible: (mensaje = 'Servicio no disponible') =>
    new AppError('SERVICIO_NO_DISPONIBLE', mensaje, 503),
} as const;

/**
 * Traduce cualquier error a la forma uniforme `{codigo, mensaje}` (§7.7).
 * Nunca expone stack traces ni detalles internos al cliente.
 */
export function manejarError(error: unknown, peticion: FastifyRequest, respuesta: FastifyReply) {
  if (error instanceof AppError) {
    return respuesta.code(error.estado).send({ codigo: error.codigo, mensaje: error.message });
  }

  if (error instanceof ZodError) {
    const mensaje = error.issues.map((issue) => issue.message).join('; ');
    return respuesta.code(400).send({ codigo: 'DATOS_INVALIDOS', mensaje });
  }

  const errorConEstado = error as { statusCode?: number; message?: string } | null;
  if (errorConEstado?.statusCode && errorConEstado.statusCode < 500) {
    return respuesta.code(errorConEstado.statusCode).send({
      codigo: 'DATOS_INVALIDOS',
      mensaje: errorConEstado.message ?? 'Solicitud inválida',
    });
  }

  peticion.log.error({ err: error }, 'error no controlado');
  return respuesta.code(500).send({ codigo: 'ERROR_INTERNO', mensaje: 'Error interno del servidor' });
}

/** Instala el manejador uniforme de errores y de rutas no encontradas. */
export function registrarManejadorErrores(app: FastifyInstance): void {
  app.setErrorHandler((error, peticion, respuesta) => manejarError(error, peticion, respuesta));

  app.setNotFoundHandler((peticion, respuesta) =>
    respuesta.code(404).send({
      codigo: 'NO_ENCONTRADO',
      mensaje: `Ruta no encontrada: ${peticion.method} ${peticion.url}`,
    }),
  );
}
