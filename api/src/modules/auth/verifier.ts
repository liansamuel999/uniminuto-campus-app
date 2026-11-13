import { SignJWT, jwtVerify } from 'jose';
import { errores } from '../../lib/errors.js';
import type { Env } from '../../config/env.js';
import { leerCuentaDeServicioFirebase } from '../../config/firebase_credentials.js';

/** Identidad autenticada que viaja adjunta a cada petición. */
export interface IdentidadToken {
  uid: string;
  roles: string[];
  correo?: string;
}

/** Contrato de verificación de ID Tokens (D-20). */
export interface TokenVerifier {
  verificar(token: string): Promise<IdentidadToken>;
}

function extraerRoles(valor: unknown): string[] {
  if (!Array.isArray(valor)) return [];
  return valor.filter((rol): rol is string => typeof rol === 'string');
}

/**
 * Verificador de desarrollo: tokens HS256 firmados con `AUTH_DEV_SECRET`.
 * Solo se instancia cuando `ENTORNO=dev`; en producción se rechaza por configuración.
 */
export class DevTokenVerifier implements TokenVerifier {
  private readonly clave: Uint8Array;

  constructor(
    secreto: string,
    private readonly emisor = 'campus-dev',
  ) {
    if (secreto.length < 16) {
      throw new Error('AUTH_DEV_SECRET debe tener al menos 16 caracteres');
    }
    this.clave = new TextEncoder().encode(secreto);
  }

  async verificar(token: string): Promise<IdentidadToken> {
    try {
      const { payload } = await jwtVerify(token, this.clave, {
        algorithms: ['HS256'],
        issuer: this.emisor,
      });
      if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
        throw new Error('El token no tiene sub');
      }
      return {
        uid: payload.sub,
        roles: extraerRoles(payload.roles),
        ...(typeof payload.email === 'string' ? { correo: payload.email } : {}),
      };
    } catch {
      throw errores.noAutorizado('Token de desarrollo inválido o vencido');
    }
  }
}

/** Datos para firmar un token de desarrollo (pruebas y comando `npm run token:dev`). */
export interface DatosTokenDev {
  uid: string;
  secreto: string;
  roles?: string[];
  correo?: string;
  emisor?: string;
  expiracion?: string;
}

/** Firma un token HS256 de desarrollo. No usar fuera de `ENTORNO=dev`. */
export async function firmarTokenDev(datos: DatosTokenDev): Promise<string> {
  const clave = new TextEncoder().encode(datos.secreto);
  const payload: Record<string, unknown> = { roles: datos.roles ?? [] };
  if (datos.correo) payload.email = datos.correo;

  return new SignJWT(payload)
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(datos.uid)
    .setIssuer(datos.emisor ?? 'campus-dev')
    .setIssuedAt()
    .setExpirationTime(datos.expiracion ?? '1h')
    .sign(clave);
}

/**
 * Acepta un token si cualquiera de los verificadores lo valida (solo en desarrollo, D-59).
 * Permite seguir usando `npm run token:dev` para pruebas de humo mientras el proyecto Firebase
 * ya está configurado y todavía no hay usuarios reales creados.
 */
export class VerificadorCompuesto implements TokenVerifier {
  constructor(private readonly verificadores: readonly TokenVerifier[]) {}

  async verificar(token: string): Promise<IdentidadToken> {
    let ultimoError: unknown;
    for (const verificador of this.verificadores) {
      try {
        return await verificador.verificar(token);
      } catch (error) {
        ultimoError = error;
      }
    }
    throw ultimoError instanceof Error ? ultimoError : errores.noAutorizado();
  }
}

/**
 * Elige el verificador según el entorno: Firebase en producción; en desarrollo, Firebase (si hay
 * cuenta de servicio) y/o tokens HS256 locales.
 *
 * `firebase-admin` se importa de forma diferida para que el arranque en desarrollo sin Firebase
 * no cargue el SDK.
 */
export async function crearVerificador(env: Env): Promise<TokenVerifier> {
  const cuentaDeServicio = leerCuentaDeServicioFirebase(env);

  if (env.ENTORNO === 'prod') {
    if (!cuentaDeServicio) {
      throw new Error(
        'En producción se requiere FIREBASE_SERVICE_ACCOUNT o FIREBASE_SERVICE_ACCOUNT_PATH',
      );
    }
    const { FirebaseTokenVerifier } = await import('./firebase_verifier.js');
    return new FirebaseTokenVerifier(cuentaDeServicio);
  }

  const verificadores: TokenVerifier[] = [];
  if (cuentaDeServicio) {
    const { FirebaseTokenVerifier } = await import('./firebase_verifier.js');
    verificadores.push(new FirebaseTokenVerifier(cuentaDeServicio));
  }
  if (env.AUTH_DEV_SECRET) {
    verificadores.push(new DevTokenVerifier(env.AUTH_DEV_SECRET));
  }

  const [primero] = verificadores;
  if (!primero) {
    throw new Error(
      'En dev se requiere AUTH_DEV_SECRET o una cuenta de servicio de Firebase para autenticar',
    );
  }
  return verificadores.length === 1 ? primero : new VerificadorCompuesto(verificadores);
}
