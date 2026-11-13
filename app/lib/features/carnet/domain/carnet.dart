/// Modelos del carnet digital (§4.2, §6.1) compartidos por la app.
class CarnetDatos {
  const CarnetDatos({
    required this.id,
    required this.codigoBarras,
    required this.estado,
    required this.vigenteHasta,
  });

  final String id;
  final String codigoBarras;
  final String estado;
  final DateTime vigenteHasta;

  bool get activo => estado == 'ACTIVO';

  static CarnetDatos fromJson(Map<String, dynamic> json) {
    return CarnetDatos(
      id: '${json['id']}',
      codigoBarras: '${json['codigoBarras']}',
      estado: '${json['estado']}',
      vigenteHasta: DateTime.tryParse('${json['vigenteHasta']}') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'codigoBarras': codigoBarras,
        'estado': estado,
        'vigenteHasta': vigenteHasta.toIso8601String(),
      };
}

class CertificadoCarnet {
  const CertificadoCarnet({
    required this.jwt,
    required this.kid,
    required this.emitidoEn,
    required this.expiraEn,
  });

  final String jwt;
  final String kid;
  final DateTime emitidoEn;
  final DateTime expiraEn;

  bool get vencido => DateTime.now().toUtc().isAfter(expiraEn);

  /// Renovación anticipada: quedan menos de 7 días (§6.1).
  bool get porVencer => DateTime.now().toUtc().isAfter(expiraEn.subtract(const Duration(days: 7)));

  static CertificadoCarnet fromJson(Map<String, dynamic> json) {
    return CertificadoCarnet(
      jwt: '${json['jwt']}',
      kid: '${json['kid']}',
      emitidoEn: DateTime.tryParse('${json['emitidoEn']}')?.toUtc() ?? DateTime.now().toUtc(),
      expiraEn: DateTime.tryParse('${json['expiraEn']}')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'jwt': jwt,
        'kid': kid,
        'emitidoEn': emitidoEn.toIso8601String(),
        'expiraEn': expiraEn.toIso8601String(),
      };
}

class ResumenCarnet {
  const ResumenCarnet({
    required this.carnet,
    this.dispositivoId,
    this.dispositivoNombre,
    this.certificado,
  });

  final CarnetDatos carnet;
  final String? dispositivoId;
  final String? dispositivoNombre;
  final CertificadoCarnet? certificado;

  bool get tieneDispositivo => dispositivoId != null;
  bool get listoParaQr => certificado != null && dispositivoId != null;

  static ResumenCarnet fromJson(Map<String, dynamic> json) {
    final certificadoJson = json['certificado'];
    final dispositivoJson = json['dispositivo'];
    return ResumenCarnet(
      carnet: CarnetDatos.fromJson(json['carnet'] as Map<String, dynamic>),
      dispositivoId: dispositivoJson is Map<String, dynamic> ? '${dispositivoJson['id']}' : null,
      dispositivoNombre: dispositivoJson is Map<String, dynamic> ? '${dispositivoJson['nombre']}' : null,
      certificado: certificadoJson is Map<String, dynamic>
          ? CertificadoCarnet.fromJson(certificadoJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'carnet': carnet.toJson(),
        if (dispositivoId != null) 'dispositivo': {'id': dispositivoId, 'nombre': dispositivoNombre},
        if (certificado != null) 'certificado': certificado!.toJson(),
      };
}

/// Estado de la pantalla del carnet.
enum EstadoCarnet { cargando, sinDispositivo, listo, certificadoVencido, error }
