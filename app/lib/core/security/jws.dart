import 'dart:convert';

/// Utilidades de JWS compacto (RFC 7515) y base64url sin relleno.

String b64urlDeBytes(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> bytesDeB64url(String texto) {
  final normalizado = base64Url.normalize(texto);
  return base64Url.decode(normalizado);
}

String b64urlDeTexto(String texto) => b64urlDeBytes(utf8.encode(texto));

String? textoDeB64url(String segmento) {
  try {
    return utf8.decode(bytesDeB64url(segmento));
  } catch (_) {
    return null;
  }
}

/// JWS compacto ya separado en sus tres partes.
class JwsPartes {
  JwsPartes({
    required this.cabecera,
    required this.payload,
    required this.entradaFirmada,
    required this.firma,
  });

  final Map<String, dynamic> cabecera;
  final Map<String, dynamic> payload;
  final String entradaFirmada;
  final List<int> firma;

  String? get kid => cabecera['kid'] as String?;

  /// Parsea un JWS compacto; devuelve `null` si el formato es inválido.
  static JwsPartes? parsear(String token) {
    final segmentos = token.split('.');
    if (segmentos.length != 3) return null;

    final cabeceraTexto = textoDeB64url(segmentos[0]);
    final payloadTexto = textoDeB64url(segmentos[1]);
    if (cabeceraTexto == null || payloadTexto == null) return null;

    try {
      final cabecera = jsonDecode(cabeceraTexto);
      final payload = jsonDecode(payloadTexto);
      if (cabecera is! Map<String, dynamic> || payload is! Map<String, dynamic>) return null;
      return JwsPartes(
        cabecera: cabecera,
        payload: payload,
        entradaFirmada: '${segmentos[0]}.${segmentos[1]}',
        firma: bytesDeB64url(segmentos[2]),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Construye y firma un JWS compacto con ES256.
Future<String> firmarJws({
  required Map<String, dynamic> cabecera,
  required Map<String, dynamic> payload,
  required Future<List<int>> Function(List<int> entrada) firmarBytes,
}) async {
  final cabeceraB64 = b64urlDeTexto(jsonEncode(cabecera));
  final payloadB64 = b64urlDeTexto(jsonEncode(payload));
  final entrada = '$cabeceraB64.$payloadB64';
  final firma = await firmarBytes(utf8.encode(entrada));
  return '$entrada.${b64urlDeBytes(firma)}';
}
