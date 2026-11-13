import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import 'device_keys.dart';
import 'jws.dart';

/// Curva P-256 usada por ES256.
final ECDomainParameters _curva = ECCurve_prime256v1();

/// Convierte una firma ECDSA a R‖S de 64 bytes (formato JWS).
Uint8List _firmaCruda(ECSignature firma) {
  final salida = Uint8List(64);
  salida.setRange(0, 32, _bigIntABytes32(firma.r));
  salida.setRange(32, 64, _bigIntABytes32(firma.s));
  return salida;
}

ECSignature _firmaDesdeBytes(List<int> firma) {
  return ECSignature(
    _bytesABigInt(firma.sublist(0, 32)),
    _bytesABigInt(firma.sublist(32, 64)),
  );
}

Uint8List _semillaSegura() {
  final azar = Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => azar.nextInt(256)));
}

Uint8List _bigIntABytes32(BigInt valor) {
  final texto = valor.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList(List<int>.generate(32, (i) => int.parse(texto.substring(i * 2, i * 2 + 2), radix: 16)));
}

BigInt _bytesABigInt(List<int> bytes) => BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );

/// Firma ES256 con la clave privada `d` (móvil/VM). Devuelve R‖S (64 bytes).
Uint8List firmarEs256ConPrivada(BigInt d, List<int> entrada) {
  final firmador = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64));
  firmador.init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, _curva)));
  final firma = firmador.generateSignature(Uint8List.fromList(entrada)) as ECSignature;
  return _firmaCruda(firma);
}

/// Verifica ES256 con la clave pública JWK.
bool verificarEs256ConJwk(Map<String, dynamic> jwk, List<int> datos, List<int> firma) {
  final x = _bytesABigInt(bytesDeB64url(jwk['x'] as String));
  final y = _bytesABigInt(bytesDeB64url(jwk['y'] as String));
  final punto = _curva.curve.createPoint(x, y);
  final verificador = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64));
  verificador.init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(punto, _curva)));
  return verificador.verifySignature(Uint8List.fromList(datos), _firmaDesdeBytes(firma));
}

/// Par ES256 generado localmente (también lo usan las pruebas).
class ParEs256 {
  const ParEs256({required this.d, required this.jwk});

  final BigInt d;
  final Map<String, dynamic> jwk;
}

/// Genera un par ECDSA P-256 y devuelve la privada (`d`) y la pública en JWK.
ParEs256 generarParEs256() {
  final azar = FortunaRandom()..seed(KeyParameter(_semillaSegura()));
  final generador = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curva), azar));
  final par = generador.generateKeyPair();

  final privada = par.privateKey;
  final publica = par.publicKey;
  return ParEs256(
    d: privada.d!,
    jwk: <String, dynamic>{
      'kty': 'EC',
      'crv': 'P-256',
      'x': b64urlDeBytes(_bigIntABytes32(publica.Q!.x!.toBigInteger()!)),
      'y': b64urlDeBytes(_bigIntABytes32(publica.Q!.y!.toBigInteger()!)),
    },
  );
}

class VerificadorEs256Movil implements VerificadorEs256 {
  const VerificadorEs256Movil();

  @override
  Future<bool> verificar(Map<String, dynamic> clavePublicaJwk, List<int> datos, List<int> firma) async {
    return verificarEs256ConJwk(clavePublicaJwk, datos, firma);
  }
}

/// Almacén en `flutter_secure_storage` (Keystore/Keychain). La clave privada no se exporta a
/// archivos ni viaja al backend (D-30).
class AlmacenClavesMovil implements AlmacenClavesDispositivo {
  AlmacenClavesMovil({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _claveAlmacen = 'campus.device.key.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<ClaveDispositivo?> cargar() async {
    final crudo = await _storage.read(key: _claveAlmacen);
    if (crudo == null) return null;
    try {
      final datos = jsonDecode(crudo) as Map<String, dynamic>;
      final d = BigInt.parse(datos['d'] as String, radix: 16);
      final jwk = <String, dynamic>{
        'kty': 'EC',
        'crv': 'P-256',
        'x': datos['x'],
        'y': datos['y'],
      };
      return ClaveDispositivo(
        clavePublicaJwk: jwk,
        huella: huellaDeJwk(jwk),
        firmarEntrada: (entrada) async => firmarEs256ConPrivada(d, entrada),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ClaveDispositivo> generar() async {
    final par = generarParEs256();
    final d = par.d;
    final jwk = par.jwk;

    await _storage.write(
      key: _claveAlmacen,
      value: jsonEncode({'d': d.toRadixString(16), 'x': jwk['x'], 'y': jwk['y']}),
    );

    return ClaveDispositivo(
      clavePublicaJwk: jwk,
      huella: huellaDeJwk(jwk),
      firmarEntrada: (entrada) async => firmarEs256ConPrivada(d, entrada),
    );
  }

  @override
  Future<void> borrar() => _storage.delete(key: _claveAlmacen);
}

/// Fábrica de plataforma (móvil / VM).
AlmacenClavesDispositivo crearAlmacenDeClaves() => AlmacenClavesMovil();

VerificadorEs256 crearVerificadorEs256() => const VerificadorEs256Movil();
