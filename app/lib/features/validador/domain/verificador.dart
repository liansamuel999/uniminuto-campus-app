import 'dart:convert';

import '../../../core/security/device_keys.dart';
import '../../../core/security/jws.dart';

/// Motivos del modo validador, en el orden en que se evalúan (§6.1).
enum MotivoValidacion {
  ok,
  formatoInvalido,
  kidDesconocido,
  firmaCertInvalida,
  certVencido,
  carnetRevocado,
  firmaQrInvalida,
  qrVencido,
  qrRepetido,
}

extension DetalleMotivo on MotivoValidacion {
  String get codigo => switch (this) {
        MotivoValidacion.ok => 'OK',
        MotivoValidacion.formatoInvalido => 'FORMATO_INVALIDO',
        MotivoValidacion.kidDesconocido => 'KID_DESCONOCIDO',
        MotivoValidacion.firmaCertInvalida => 'FIRMA_CERT_INVALIDA',
        MotivoValidacion.certVencido => 'CERT_VENCIDO',
        MotivoValidacion.carnetRevocado => 'CARNET_REVOCADO',
        MotivoValidacion.firmaQrInvalida => 'FIRMA_QR_INVALIDA',
        MotivoValidacion.qrVencido => 'QR_VENCIDO',
        MotivoValidacion.qrRepetido => 'QR_REPETIDO',
      };

  String get mensaje => switch (this) {
        MotivoValidacion.ok => 'Acceso permitido',
        MotivoValidacion.formatoInvalido => 'El código no tiene el formato esperado',
        MotivoValidacion.kidDesconocido => 'Certificado emitido con una clave desconocida',
        MotivoValidacion.firmaCertInvalida => 'La firma del certificado no es válida',
        MotivoValidacion.certVencido => 'El certificado del carnet está vencido',
        MotivoValidacion.carnetRevocado => 'El carnet está revocado o inactivo',
        MotivoValidacion.firmaQrInvalida => 'La firma del QR no es válida',
        MotivoValidacion.qrVencido => 'El QR está vencido',
        MotivoValidacion.qrRepetido => 'Este QR ya fue usado (posible captura de pantalla)',
      };
}

class ResultadoValidacion {
  const ResultadoValidacion({
    required this.motivo,
    this.carnetId,
    this.codigo,
    this.expiraEn,
  });

  final MotivoValidacion motivo;
  final String? carnetId;
  final String? codigo;
  final DateTime? expiraEn;

  bool get permitido => motivo == MotivoValidacion.ok;

  String get motivoCodigo => motivo.codigo;
}

/// Caché anti-repetición de `jti` (5 minutos, §6.1).
abstract class CacheJti {
  bool contiene(String jti);

  Future<void> registrar(String jti, DateTime ahora);
}

/// Carnets revocados descargados por el validador (D-32).
abstract class ListaRevocados {
  bool contiene(String carnetId);
}

/// Verificación offline del QR con las 7 reglas de §6.1.
class VerificadorCarnet {
  VerificadorCarnet({
    required this.verificadorFirma,
    required this.clavesPorKid,
    required this.cacheJti,
    required this.revocados,
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;

  static const Duration toleranciaCertificado = Duration(seconds: 60);
  static const Duration toleranciaToken = Duration(seconds: 30);

  final VerificadorEs256 verificadorFirma;
  final Map<String, Map<String, dynamic>> clavesPorKid;
  final CacheJti cacheJti;
  final ListaRevocados revocados;
  final DateTime Function() _reloj;

  Future<ResultadoValidacion> validar(String qr) async {
    final ahora = _reloj().toUtc();
    final segmentos = qr.trim().split('.');

    // 1. Formato válido y `kid` conocido.
    if (segmentos.length != 6) {
      return _fallo(MotivoValidacion.formatoInvalido);
    }
    final certificado = JwsPartes.parsear(segmentos.take(3).join('.'));
    final token = JwsPartes.parsear(segmentos.skip(3).join('.'));
    if (certificado == null || token == null) {
      return _fallo(MotivoValidacion.formatoInvalido);
    }
    final kid = certificado.kid;
    final claveInstitucional = kid == null ? null : clavesPorKid[kid];
    if (claveInstitucional == null) {
      return _fallo(MotivoValidacion.kidDesconocido);
    }

    // 2. Firma del certificado con la clave pública institucional.
    final firmaCertificadoOk = await verificadorFirma.verificar(
      claveInstitucional,
      utf8.encode(certificado.entradaFirmada),
      certificado.firma,
    );
    if (!firmaCertificadoOk) {
      return _fallo(MotivoValidacion.firmaCertInvalida);
    }

    // 3. Certificado no vencido (tolerancia de reloj ±60 s).
    final expCertificado = _epoch(certificado.payload['exp']);
    if (expCertificado == null) return _fallo(MotivoValidacion.formatoInvalido);
    final expiraCertificado = DateTime.fromMillisecondsSinceEpoch(expCertificado * 1000, isUtc: true);
    if (ahora.isAfter(expiraCertificado.add(toleranciaCertificado))) {
      return _fallo(MotivoValidacion.certVencido);
    }

    // 4. Estado ACTIVO y carnet fuera de la lista de revocación local.
    final carnetId = certificado.payload['sub'] as String?;
    final estado = certificado.payload['est'] as String?;
    if (carnetId == null || estado == null) {
      return _fallo(MotivoValidacion.formatoInvalido);
    }
    if (estado != 'ACTIVO' || revocados.contiene(carnetId)) {
      return _fallo(MotivoValidacion.carnetRevocado, carnetId: carnetId);
    }

    // 5. Firma del token QR con la clave del dispositivo (`cnf`).
    final cnf = certificado.payload['cnf'];
    if (cnf is! Map<String, dynamic>) {
      return _fallo(MotivoValidacion.formatoInvalido, carnetId: carnetId);
    }
    final firmaTokenOk = await verificadorFirma.verificar(
      cnf,
      utf8.encode(token.entradaFirmada),
      token.firma,
    );
    if (!firmaTokenOk) {
      return _fallo(MotivoValidacion.firmaQrInvalida, carnetId: carnetId);
    }

    // 6. Token no vencido (60 s, tolerancia ±30 s).
    final expToken = _epoch(token.payload['exp']);
    if (expToken == null) return _fallo(MotivoValidacion.formatoInvalido, carnetId: carnetId);
    final expiraToken = DateTime.fromMillisecondsSinceEpoch(expToken * 1000, isUtc: true);
    if (ahora.isAfter(expiraToken.add(toleranciaToken))) {
      return _fallo(MotivoValidacion.qrVencido, carnetId: carnetId);
    }

    // 7. `jti` no visto en los últimos 5 minutos.
    final jti = token.payload['jti'] as String?;
    if (jti == null || token.payload['sub'] != carnetId) {
      return _fallo(MotivoValidacion.formatoInvalido, carnetId: carnetId);
    }
    if (cacheJti.contiene(jti)) {
      return _fallo(MotivoValidacion.qrRepetido, carnetId: carnetId);
    }
    await cacheJti.registrar(jti, ahora);

    return ResultadoValidacion(
      motivo: MotivoValidacion.ok,
      carnetId: carnetId,
      codigo: certificado.payload['cod'] as String?,
      expiraEn: expiraCertificado,
    );
  }

  ResultadoValidacion _fallo(MotivoValidacion motivo, {String? carnetId}) {
    return ResultadoValidacion(motivo: motivo, carnetId: carnetId);
  }

  int? _epoch(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return null;
  }
}
