import 'dart:math';

import '../../../core/security/device_keys.dart';
import '../../../core/security/jws.dart';
import '../domain/carnet.dart';

/// Token QR dinámico (§6.1): JWT ES256 firmado con la clave del dispositivo.
///
/// Claims: `sub` (id de carnet), `jti` (contador + aleatorio), `iat`, `exp` (60 s).
/// No lleva foto, nombre ni datos personales.
class ServicioQr {
  ServicioQr({
    required this.carnet,
    required this.certificado,
    required ClaveDispositivo clave,
  }) : _clave = clave;

  static const Duration vigenciaToken = Duration(seconds: 60);

  final CarnetDatos carnet;
  final CertificadoCarnet certificado;
  final ClaveDispositivo _clave;

  int _contador = 0;
  final Random _azar = Random.secure();

  /// Cadena compacta `<certificado>.<tokenQR>` (6 segmentos; D-26).
  Future<String> generar(DateTime ahora) async {
    final iat = ahora.toUtc().millisecondsSinceEpoch ~/ 1000;
    final jti = '${_contador++}.${_sufijoAleatorio()}';
    final token = await firmarJws(
      cabecera: const {'alg': 'ES256', 'typ': 'JWT'},
      payload: {
        'sub': carnet.id,
        'jti': jti,
        'iat': iat,
        'exp': iat + vigenciaToken.inSeconds,
      },
      firmarBytes: _clave.firmarEntrada,
    );
    return '${certificado.jwt}.$token';
  }

  String _sufijoAleatorio() {
    const alfabeto = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(6, (_) => alfabeto[_azar.nextInt(alfabeto.length)]).join();
  }
}
