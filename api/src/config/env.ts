import { z } from 'zod';

/**
 * Configuración de la API validada al arrancar (§7.2, D-16).
 * Si falta una variable o su formato es inválido, el proceso falla rápido con un mensaje claro.
 */
export const envSchema = z
  .object({
    ENTORNO: z.enum(['dev', 'prod']).default('dev'),
    PORT: z.coerce.number().int().positive().max(65_535).default(3000),
    LOG_LEVEL: z
      .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
      .default('info'),
    DATABASE_URL: z.string().min(1, 'DATABASE_URL es obligatoria'),
    CORS_ORIGINS: z.string().default('http://localhost:5173,http://127.0.0.1:5173'),
    /** Solo desarrollo: secreto HS256 para tokens de prueba (D-20). */
    AUTH_DEV_SECRET: z.string().min(16, 'AUTH_DEV_SECRET debe tener al menos 16 caracteres').optional(),
    /** JSON de la cuenta de servicio de Firebase, en una sola línea. */
    FIREBASE_SERVICE_ACCOUNT: z.string().min(2).optional(),
    /** Ruta al JSON de la cuenta de servicio; relativa a `api/` (D-59). */
    FIREBASE_SERVICE_ACCOUNT_PATH: z.string().min(2).optional(),
    S3_ENDPOINT: z.string().url().optional(),
    S3_ACCESS_KEY: z.string().optional(),
    S3_SECRET_KEY: z.string().optional(),
    S3_BUCKET: z.string().default('campus-app'),
    S3_REGION: z.string().default('us-east-1'),
    UPLOAD_MAX_BYTES: z.coerce.number().int().positive().default(52_428_800),
    ENTREGA_GRACIA_HORAS: z.coerce.number().int().nonnegative().default(24),
  })
  .superRefine((valores, ctx) => {
    if (valores.ENTORNO === 'prod' && valores.AUTH_DEV_SECRET) {
      ctx.addIssue({
        code: 'custom',
        path: ['AUTH_DEV_SECRET'],
        message: 'AUTH_DEV_SECRET no puede estar presente en producción',
      });
    }
    if (
      valores.ENTORNO === 'dev' &&
      !valores.AUTH_DEV_SECRET &&
      !valores.FIREBASE_SERVICE_ACCOUNT &&
      !valores.FIREBASE_SERVICE_ACCOUNT_PATH
    ) {
      ctx.addIssue({
        code: 'custom',
        path: ['AUTH_DEV_SECRET'],
        message:
          'En dev se requiere AUTH_DEV_SECRET, FIREBASE_SERVICE_ACCOUNT o FIREBASE_SERVICE_ACCOUNT_PATH para autenticar',
      });
    }
    if ((valores.S3_ACCESS_KEY && !valores.S3_SECRET_KEY) || (!valores.S3_ACCESS_KEY && valores.S3_SECRET_KEY)) {
      ctx.addIssue({
        code: 'custom',
        path: ['S3_ACCESS_KEY'],
        message: 'S3_ACCESS_KEY y S3_SECRET_KEY deben configurarse juntas',
      });
    }
  });

export type Env = z.infer<typeof envSchema>;

/**
 * Un archivo `.env` deja las variables vacías como cadena vacía (`CLAVE=`), no como `undefined`.
 * Se normaliza antes de validar para que "vacío" signifique "no configurado".
 */
function normalizarEntorno(origen: NodeJS.ProcessEnv): Record<string, string> {
  const limpio: Record<string, string> = {};
  for (const [clave, valor] of Object.entries(origen)) {
    if (typeof valor === 'string' && valor.trim() !== '') {
      limpio[clave] = valor;
    }
  }
  return limpio;
}

/** Valida el entorno y devuelve la configuración tipada. */
export function cargarEnv(origen: NodeJS.ProcessEnv = process.env): Env {
  const resultado = envSchema.safeParse(normalizarEntorno(origen));
  if (!resultado.success) {
    const detalle = resultado.error.issues
      .map((issue) => `${issue.path.join('.') || '(raíz)'}: ${issue.message}`)
      .join('; ');
    throw new Error(`Configuración de entorno inválida → ${detalle}`);
  }
  return resultado.data;
}

/** Lista de orígenes permitidos por CORS (D-22). */
export function origenesCors(env: Env): string[] {
  return env.CORS_ORIGINS.split(',')
    .map((origen) => origen.trim())
    .filter((origen) => origen.length > 0);
}
