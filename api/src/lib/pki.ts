import { SignJWT, importJWK, jwtVerify, type JWK } from 'jose';

import type { ClaveInstitucional, JwkEc } from '../config/institution_keys.js';

type LlaveImportada = Awaited<ReturnType<typeof importJWK>>;

/** Emisor de los certificados de carnet (§6.1). */
export const EMISOR_CARNET = 'uniminuto-campus-app';

export const VIGENCIA_CERTIFICADO_DIAS = 30;

export interface DatosCertificado {
  carnetId: string;
  codigo: string;
  estado: string;
  dispositivo: JwkEc;
  vigenciaDias?: number;
}

export interface CertificadoEmitido {
  jwt: string;
  kid: string;
  emitidoEn: Date;
  expiraEn: Date;
}

/** Firma certificados de carnet con la clave institucional ES256 (§6.1). */
export class FirmanteCarnet {
  private constructor(
    private readonly clave: ClaveInstitucional,
    private readonly llave: LlaveImportada,
    readonly emisor: string,
  ) {}

  static async crear(clave: ClaveInstitucional, emisor: string = EMISOR_CARNET): Promise<FirmanteCarnet> {
    const llave = await importJWK(clave.privada as unknown as JWK, 'ES256');
    return new FirmanteCarnet(clave, llave, emisor);
  }

  get kid(): string {
    return this.clave.kid;
  }

  get clavePublica(): JwkEc {
    return this.clave.publica;
  }

  /**
   * Claims del certificado: `iss`, `sub` (id de carnet), `cod`, `est`, `cnf` (JWK del dispositivo),
   * `iat` y `exp` (30 días). No se añaden datos personales (§6.1).
   */
  async firmar(datos: DatosCertificado, ahora: Date = new Date()): Promise<CertificadoEmitido> {
    const dias = datos.vigenciaDias ?? VIGENCIA_CERTIFICADO_DIAS;
    const emitidoEn = ahora;
    const expiraEn = new Date(ahora.getTime() + dias * 24 * 60 * 60 * 1000);

    const jwt = await new SignJWT({
      cod: datos.codigo,
      est: datos.estado,
      cnf: datos.dispositivo,
    })
      .setProtectedHeader({ alg: 'ES256', kid: this.clave.kid, typ: 'JWT' })
      .setIssuer(this.emisor)
      .setSubject(datos.carnetId)
      .setIssuedAt(Math.floor(emitidoEn.getTime() / 1000))
      .setExpirationTime(Math.floor(expiraEn.getTime() / 1000))
      .sign(this.llave);

    return { jwt, kid: this.clave.kid, emitidoEn, expiraEn };
  }
}

/** Verificación de un certificado (pruebas y, en la app, el modo validador). */
export async function verificarCertificado(
  jwt: string,
  clavePublica: JwkEc,
  emisor: string = EMISOR_CARNET,
): Promise<Record<string, unknown>> {
  const llave = await importJWK(clavePublica as unknown as JWK, 'ES256');
  const { payload } = await jwtVerify(jwt, llave, { algorithms: ['ES256'], issuer: emisor });
  return payload as Record<string, unknown>;
}
