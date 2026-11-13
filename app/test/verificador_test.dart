import 'package:campus_app/core/security/almacen_movil.dart';
import 'package:campus_app/core/security/jws.dart';
import 'package:campus_app/features/validador/domain/verificador.dart';
import 'package:flutter_test/flutter_test.dart';

class CacheJtiMemoria implements CacheJti {
  final Map<String, DateTime> vistos = {};

  @override
  bool contiene(String jti) => vistos.containsKey(jti);

  @override
  Future<void> registrar(String jti, DateTime ahora) async => vistos[jti] = ahora;
}

class RevocadosMemoria implements ListaRevocados {
  RevocadosMemoria([Set<String>? ids]) : ids = ids ?? {};

  final Set<String> ids;

  @override
  bool contiene(String carnetId) => ids.contains(carnetId);
}

const String carnetId = '3f1c2b4a-1111-4a2b-9c3d-000000000001';
const String kid = 'inst-test';

Future<String> firmarAsync(ParEs256 par, Map<String, dynamic> payload, {String? kidCabecera}) {
  return firmarJws(
    cabecera: {'alg': 'ES256', 'typ': 'JWT', if (kidCabecera != null) 'kid': kidCabecera},
    payload: payload,
    firmarBytes: (bytes) async => firmarEs256ConPrivada(par.d, bytes),
  );
}

void main() {
  late ParEs256 institucional;
  late ParEs256 dispositivo;
  late DateTime ahora;
  late CacheJtiMemoria cache;
  late RevocadosMemoria revocados;

  setUp(() {
    institucional = generarParEs256();
    dispositivo = generarParEs256();
    ahora = DateTime.utc(2026, 11, 13, 12);
    cache = CacheJtiMemoria();
    revocados = RevocadosMemoria();
  });

  Future<String> certificado({int diasValidez = 30, String estado = 'ACTIVO', String? kidCabecera = kid}) {
    final iat = ahora.millisecondsSinceEpoch ~/ 1000;
    return firmarAsync(
      institucional,
      {
        'iss': 'uniminuto-campus-app',
        'sub': carnetId,
        'cod': 'UNI-20261001',
        'est': estado,
        'cnf': dispositivo.jwk,
        'iat': iat,
        'exp': iat + diasValidez * 86400,
      },
      kidCabecera: kidCabecera,
    );
  }

  Future<String> token({int segundosValidez = 60, String jti = '0.abc123', ParEs256? firmante}) {
    final iat = ahora.millisecondsSinceEpoch ~/ 1000;
    return firmarAsync(
      firmante ?? dispositivo,
      {'sub': carnetId, 'jti': jti, 'iat': iat, 'exp': iat + segundosValidez},
    );
  }

  VerificadorCarnet verificador() {
    return VerificadorCarnet(
      verificadorFirma: const VerificadorEs256Movil(),
      clavesPorKid: {kid: institucional.jwk},
      cacheJti: cache,
      revocados: revocados,
      reloj: () => ahora,
    );
  }

  Future<String> qrValido({String jti = '0.abc123'}) async {
    return '${await certificado()}.${await token(jti: jti)}';
  }

  test('QR válido → PERMITIDO', () async {
    final resultado = await verificador().validar(await qrValido());
    expect(resultado.motivo, MotivoValidacion.ok);
    expect(resultado.codigo, 'UNI-20261001');
  });

  test('1. formato inválido', () async {
    final resultado = await verificador().validar('esto-no-es-un-qr');
    expect(resultado.motivo, MotivoValidacion.formatoInvalido);
  });

  test('2. kid desconocido', () async {
    final qr = '${await certificado(kidCabecera: 'otro-kid')}.${await token()}';
    final resultado = await verificador().validar(qr);
    expect(resultado.motivo, MotivoValidacion.kidDesconocido);
  });

  test('3. firma del certificado inválida', () async {
    final qr = await qrValido();
    final segmentos = qr.split('.');
    final firma = segmentos[2];
    segmentos[2] = '${firma.substring(0, firma.length - 2)}AA';
    final resultado = await verificador().validar(segmentos.join('.'));
    expect(resultado.motivo, MotivoValidacion.firmaCertInvalida);
  });

  test('4. certificado vencido (más de 60 s)', () async {
    final iat = ahora.millisecondsSinceEpoch ~/ 1000;
    final vencido = await firmarAsync(institucional, {
      'iss': 'uniminuto-campus-app',
      'sub': carnetId,
      'cod': 'UNI-20261001',
      'est': 'ACTIVO',
      'cnf': dispositivo.jwk,
      'iat': iat - 100000,
      'exp': iat - 120,
    }, kidCabecera: kid);
    final resultado = await verificador().validar('$vencido.${await token()}');
    expect(resultado.motivo, MotivoValidacion.certVencido);
  });

  test('5. carnet revocado', () async {
    revocados.ids.add(carnetId);
    final resultado = await verificador().validar(await qrValido());
    expect(resultado.motivo, MotivoValidacion.carnetRevocado);
  });

  test('6. firma del QR inválida (otra clave)', () async {
    final otro = generarParEs256();
    final qr = '${await certificado()}.${await token(firmante: otro)}';
    final resultado = await verificador().validar(qr);
    expect(resultado.motivo, MotivoValidacion.firmaQrInvalida);
  });

  test('7. QR vencido (más de 30 s)', () async {
    final qr = '${await certificado()}.${await token(segundosValidez: -60)}';
    final resultado = await verificador().validar(qr);
    expect(resultado.motivo, MotivoValidacion.qrVencido);
  });

  test('8. QR repetido (anti-repetición de 5 minutos)', () async {
    final qr = await qrValido(jti: '7.repetido');
    expect((await verificador().validar(qr)).motivo, MotivoValidacion.ok);
    expect((await verificador().validar(qr)).motivo, MotivoValidacion.qrRepetido);
  });

  test('certificado con estado distinto de ACTIVO se deniega', () async {
    final qr = '${await certificado(estado: 'SUSPENDIDO')}.${await token()}';
    final resultado = await verificador().validar(qr);
    expect(resultado.motivo, MotivoValidacion.carnetRevocado);
  });
}
