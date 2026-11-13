import type { FastifyInstance } from 'fastify';

/** Estado de cada dependencia en la comprobación de salud. */
export type EstadoComponente = 'ok' | 'error' | 'no_configurado';

/** Dependencias inyectables para poder probar `/health` sin infraestructura. */
export interface ChequeosSalud {
  baseDeDatos: () => Promise<boolean>;
  /** Si se omite, el almacenamiento se informa como `no_configurado`. */
  almacenamiento?: () => Promise<boolean>;
}

export interface RespuestaSalud {
  estado: 'ok' | 'degradado';
  db: EstadoComponente;
  storage: EstadoComponente;
  version: string;
}

const VERSION_API = '0.1.0';
const LIMITE_CHEQUEO_MS = 2_000;

/** Ejecuta una comprobación con límite de tiempo; un fallo o un timeout cuentan como error. */
async function conLimiteTiempo(chequeo: () => Promise<boolean>): Promise<boolean> {
  let temporizador: NodeJS.Timeout | undefined;
  try {
    const limite = new Promise<boolean>((resolver) => {
      temporizador = setTimeout(() => resolver(false), LIMITE_CHEQUEO_MS);
    });
    return await Promise.race([chequeo().catch(() => false), limite]);
  } finally {
    if (temporizador) clearTimeout(temporizador);
  }
}

/**
 * `GET /health` (§7.7, D-19): sin autenticación, comprueba base de datos y almacenamiento.
 * Responde 200 si todo está `ok` (o el almacenamiento no está configurado) y 503 en otro caso.
 */
export function registrarRutasSalud(app: FastifyInstance, chequeos: ChequeosSalud): void {
  app.get('/health', async (_peticion, respuesta) => {
    const [baseDeDatosOk, almacenamientoOk] = await Promise.all([
      conLimiteTiempo(chequeos.baseDeDatos),
      chequeos.almacenamiento ? conLimiteTiempo(chequeos.almacenamiento) : Promise.resolve(true),
    ]);

    const db: EstadoComponente = baseDeDatosOk ? 'ok' : 'error';
    const storage: EstadoComponente = chequeos.almacenamiento
      ? almacenamientoOk
        ? 'ok'
        : 'error'
      : 'no_configurado';

    const cuerpo: RespuestaSalud = {
      estado: db === 'ok' && storage !== 'error' ? 'ok' : 'degradado',
      db,
      storage,
      version: VERSION_API,
    };

    return respuesta.code(cuerpo.estado === 'ok' ? 200 : 503).send(cuerpo);
  });
}
