import { describe, expect, it } from 'vitest';
import type { ClaveInstitucional, JwkEc } from '../src/config/institution_keys.js';
import { FirmanteCarnet, EMISOR_CARNET, verificarCertificado } from '../src/lib/pki.js';

async function parInstitucional(): Promise<ClaveInstitucional> {
  const par = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
  const privada = (await crypto.subtle.exportKey('jwk', par.privateKey)) as JwkEc;
  const publica = (await crypto.subtle.exportKey('jwk', par.publicKey)) as JwkEc;
  return {
    kid: 'inst-test-1',
    privada,
    publica: { ...publica, kid: 'inst-test-1', alg: 'ES256', use: 'sig' },
  };
}

async function claveDeDispositivo(): Promise<JwkEc> {
  const par = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
  return (await crypto.subtle.exportKey('jwk', par.publicKey)) as JwkEc;
}

const CARNET_ID = '3f1c2b4a-1111-4a2b-9c3d-000000000001';

describe('certificado de carnet (§6.1)', () => {
  it('firma con ES256 y el kid institucional, con vida de 30 días', async () => {
    const clave = await parInstitucional();
    const firmante = await FirmanteCarnet.crear(clave);
    const dispositivo = await claveDeDispositivo();

    const certificado = await firmante.firmar({
      carnetId: CARNET_ID,
      codigo: 'UNI-20261001',
      estado: 'ACTIVO',
      dispositivo,
    });

    expect(certificado.kid).toBe('inst-test-1');
    const dias = (certificado.expiraEn.getTime() - certificado.emitidoEn.getTime()) / 86_400_000;
    expect(dias).toBeCloseTo(30, 5);

    const claims = await verificarCertificado(certificado.jwt, clave.publica);
    expect(claims['sub']).toBe(CARNET_ID);
    expect(claims['cod']).toBe('UNI-20261001');
    expect(claims['est']).toBe('ACTIVO');
    expect(claims['iss']).toBe(EMISOR_CARNET);
    expect(claims['cnf']).toMatchObject({ kty: 'EC', crv: 'P-256', x: dispositivo.x });
    // El certificado no incluye datos personales.
    expect(claims['nombre']).toBeUndefined();
    expect(claims['foto']).toBeUndefined();
  });

  it('rechaza un certificado alterado', async () => {
    const clave = await parInstitucional();
    const firmante = await FirmanteCarnet.crear(clave);
    const certificado = await firmante.firmar({
      carnetId: CARNET_ID,
      codigo: 'UNI-20261001',
      estado: 'ACTIVO',
      dispositivo: await claveDeDispositivo(),
    });

    const [cabecera, payload, firma] = certificado.jwt.split('.');
    const alterado = `${cabecera}.${payload}.${firma?.slice(0, -4)}AAAA`;

    await expect(verificarCertificado(alterado, clave.publica)).rejects.toThrow();
  });

  it('rechaza un certificado firmado por otra clave', async () => {
    const firmante = await FirmanteCarnet.crear(await parInstitucional());
    const otra = await parInstitucional();
    const certificado = await firmante.firmar({
      carnetId: CARNET_ID,
      codigo: 'UNI-20261001',
      estado: 'ACTIVO',
      dispositivo: await claveDeDispositivo(),
    });

    await expect(verificarCertificado(certificado.jwt, otra.publica)).rejects.toThrow();
  });
});
