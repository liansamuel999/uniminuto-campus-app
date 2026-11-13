import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../carnet/domain/carnet.dart';
import '../domain/verificador.dart';

/// `jti` vistos en los últimos 5 minutos, persistidos para sobrevivir al cierre de la app (§6.1).
class CacheJtiHive implements CacheJti {
  CacheJtiHive(this._caja, {this.ventana = const Duration(minutes: 5)});

  static const String _prefijo = 'jti:';

  final Box<dynamic> _caja;
  final Duration ventana;

  @override
  bool contiene(String jti) {
    final valor = _caja.get('$_prefijo$jti');
    if (valor is! int) return false;
    final visto = DateTime.fromMillisecondsSinceEpoch(valor, isUtc: true);
    if (DateTime.now().toUtc().difference(visto) > ventana) {
      _caja.delete('$_prefijo$jti');
      return false;
    }
    return true;
  }

  @override
  Future<void> registrar(String jti, DateTime ahora) async {
    await _caja.put('$_prefijo$jti', ahora.toUtc().millisecondsSinceEpoch);
    await _purgar(ahora.toUtc());
  }

  Future<void> _purgar(DateTime ahora) async {
    final claves = _caja.keys.whereType<String>().where((clave) => clave.startsWith(_prefijo)).toList();
    for (final clave in claves) {
      final valor = _caja.get(clave);
      if (valor is! int) continue;
      final visto = DateTime.fromMillisecondsSinceEpoch(valor, isUtc: true);
      if (ahora.difference(visto) > ventana) {
        await _caja.delete(clave);
      }
    }
  }
}

/// Lista de revocación local del validador (D-32).
class ListaRevocadosHive implements ListaRevocados {
  ListaRevocadosHive(this._caja);

  static const String _claveCarnets = 'revocados';
  static const String _claveVersion = 'revocados_version';
  static const String _claveActualizado = 'revocados_actualizado_en';

  final Box<dynamic> _caja;

  @override
  bool contiene(String carnetId) {
    final valor = _caja.get(_claveCarnets);
    return valor is List && valor.contains(carnetId);
  }

  int get version => _caja.get(_claveVersion) as int? ?? 0;

  DateTime? get actualizadoEn {
    final crudo = _caja.get(_claveActualizado) as String?;
    return crudo == null ? null : DateTime.tryParse(crudo);
  }

  Future<void> actualizar({required List<String> carnets, required int version, DateTime? actualizadoEn}) async {
    await _caja.put(_claveCarnets, carnets);
    await _caja.put(_claveVersion, version);
    if (actualizadoEn != null) {
      await _caja.put(_claveActualizado, actualizadoEn.toUtc().toIso8601String());
    }
  }
}

/// Cola local de eventos de validación pendientes de subir (§6.1).
class ColaEventos {
  ColaEventos(this._caja);

  static const String _clave = 'pendientes';

  final Box<dynamic> _caja;

  List<Map<String, dynamic>> pendientes() {
    final valor = _caja.get(_clave);
    if (valor is! List) return const [];
    return valor.whereType<Map>().map((evento) => Map<String, dynamic>.from(evento)).toList();
  }

  Future<void> agregar(ResultadoValidacion resultado, {required DateTime cuando}) async {
    final lista = pendientes();
    lista.add({
      'id': _uuid(cuando),
      'timestamp': cuando.toUtc().toIso8601String(),
      'carnetId': resultado.carnetId,
      'resultado': resultado.motivoCodigo,
    });
    await _caja.put(_clave, lista);
  }

  Future<void> eliminar(List<String> ids) async {
    final restantes = pendientes().where((evento) => !ids.contains('${evento['id']}')).toList();
    await _caja.put(_clave, restantes);
  }

  /// Identificador único local (UUID v4 simplificado) para la idempotencia del lote.
  String _uuid(DateTime ahora) {
    final aleatorio = List<int>.generate(16, (indice) => (ahora.microsecondsSinceEpoch >> (indice % 8)) & 0xff ^ indice);
    aleatorio[6] = (aleatorio[6] & 0x0f) | 0x40;
    aleatorio[8] = (aleatorio[8] & 0x3f) | 0x80;
    String hex(int valor) => valor.toRadixString(16).padLeft(2, '0');
    final texto = aleatorio.map(hex).join();
    return '${texto.substring(0, 8)}-${texto.substring(8, 12)}-${texto.substring(12, 16)}-'
        '${texto.substring(16, 20)}-${texto.substring(20)}';
  }
}

/// Historial local de validaciones para mostrar en el modo validador.
class HistorialValidaciones {
  HistorialValidaciones(this._caja);

  static const String _clave = 'historial';
  static const int _maximo = 50;

  final Box<dynamic> _caja;

  List<Map<String, dynamic>> recientes() {
    final valor = _caja.get(_clave);
    if (valor is! List) return const [];
    return valor.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).take(_maximo).toList();
  }

  Future<void> agregar(ResultadoValidacion resultado, {required DateTime cuando}) async {
    final lista = recientes()
      ..insert(0, {
        'cuando': cuando.toUtc().toIso8601String(),
        'motivo': resultado.motivoCodigo,
        'permitido': resultado.permitido,
        'carnetId': resultado.carnetId,
        'codigo': resultado.codigo,
      });
    await _caja.put(_clave, lista.take(_maximo).toList());
  }
}

/// Serializa/deserializa un certificado para la caché del carnet.
Map<String, dynamic> certificadoParaCache(CertificadoCarnet certificado) => jsonDecode(
      jsonEncode(certificado.toJson()),
    ) as Map<String, dynamic>;
