import 'dart:convert';

import 'jws.dart';

/// Par de claves del dispositivo: la privada nunca sale del almacén seguro
/// (Keystore/`flutter_secure_storage` en móvil) o de WebCrypto no exportable en Web (D-29, D-30).
class ClaveDispositivo {
  const ClaveDispositivo({
    required this.clavePublicaJwk,
    required this.huella,
    required this.firmarEntrada,
  });

  final Map<String, dynamic> clavePublicaJwk;

  /// Thumbprint RFC 7638 de la clave pública, para deduplicar dispositivos.
  final String huella;

  /// Firma bytes con ES256 y devuelve la firma cruda (R‖S, 64 bytes).
  final Future<List<int>> Function(List<int> entrada) firmarEntrada;
}

/// Almacén de la clave del dispositivo según la plataforma.
abstract class AlmacenClavesDispositivo {
  Future<ClaveDispositivo?> cargar();

  Future<ClaveDispositivo> generar();

  Future<void> borrar();
}

/// Contrato mínimo para verificar firmas ES256 (Web usa WebCrypto; móvil, pointycastle).
abstract class VerificadorEs256 {
  Future<bool> verificar(Map<String, dynamic> clavePublicaJwk, List<int> datos, List<int> firma);
}

/// Huella RFC 7638: SHA-256 del JSON canónico {crv,kty,x,y} en base64url.
String huellaDeJwk(Map<String, dynamic> jwk) {
  final canonico = jsonEncode({
    'crv': jwk['crv'],
    'kty': jwk['kty'],
    'x': jwk['x'],
    'y': jwk['y'],
  });
  return b64urlDeBytes(sha256DeTexto(canonico));
}

/// SHA-256 implementado aquí para no arrastrar dependencias en la ruta crítica.
List<int> sha256DeTexto(String texto) {
  return _Sha256.calcular(utf8.encode(texto));
}

/// Implementación compacta de SHA-256 (FIPS 180-4) para la huella y el `jti`.
class _Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static List<int> calcular(List<int> datos) {
    final bits = datos.length * 8;
    final conRelleno = <int>[...datos, 0x80];
    while (conRelleno.length % 64 != 56) {
      conRelleno.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      conRelleno.add((bits >> (i * 8)) & 0xff);
    }

    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
    const mask = 0xffffffff;

    int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & mask;

    for (var bloque = 0; bloque < conRelleno.length; bloque += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        final base = bloque + i * 4;
        w[i] = ((conRelleno[base] << 24) |
                (conRelleno[base + 1] << 16) |
                (conRelleno[base + 2] << 8) |
                conRelleno[base + 3]) &
            mask;
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & mask;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e & mask) & g);
        final temp1 = (h + s1 + ch + _k[i] + w[i]) & mask;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & mask;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & mask;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & mask;
      }

      h0 = (h0 + a) & mask;
      h1 = (h1 + b) & mask;
      h2 = (h2 + c) & mask;
      h3 = (h3 + d) & mask;
      h4 = (h4 + e) & mask;
      h5 = (h5 + f) & mask;
      h6 = (h6 + g) & mask;
      h7 = (h7 + h) & mask;
    }

    final salida = <int>[];
    for (final valor in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      salida
        ..add((valor >> 24) & 0xff)
        ..add((valor >> 16) & 0xff)
        ..add((valor >> 8) & 0xff)
        ..add(valor & 0xff);
    }
    return salida;
  }
}
