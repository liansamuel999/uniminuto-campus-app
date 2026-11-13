import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { errores } from '../../lib/errors.js';
import type { IdentidadToken, TokenVerifier } from './verifier.js';

interface CredencialesServicio {
  project_id: string;
  client_email: string;
  private_key: string;
}

/**
 * Verificador de ID Tokens de Firebase Authentication (§8, D-20).
 * Comprueba firma, emisor, expiración y revocación con el Admin SDK.
 */
export class FirebaseTokenVerifier implements TokenVerifier {
  private readonly app: App;

  constructor(cuentaDeServicioJson: string) {
    let credenciales: CredencialesServicio;
    try {
      credenciales = JSON.parse(cuentaDeServicioJson) as CredencialesServicio;
    } catch {
      throw new Error('FIREBASE_SERVICE_ACCOUNT no es un JSON válido');
    }
    if (!credenciales.project_id || !credenciales.client_email || !credenciales.private_key) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT no tiene project_id, client_email o private_key');
    }

    this.app =
      getApps()[0] ??
      initializeApp({
        credential: cert({
          projectId: credenciales.project_id,
          clientEmail: credenciales.client_email,
          privateKey: credenciales.private_key,
        }),
      });
  }

  async verificar(token: string): Promise<IdentidadToken> {
    try {
      const decodificado = await getAuth(this.app).verifyIdToken(token, true);
      return {
        uid: decodificado.uid,
        roles: Array.isArray(decodificado.roles)
          ? (decodificado.roles as unknown[]).filter((rol): rol is string => typeof rol === 'string')
          : [],
        ...(decodificado.email ? { correo: decodificado.email } : {}),
      };
    } catch {
      throw errores.noAutorizado('ID Token de Firebase inválido o revocado');
    }
  }
}
