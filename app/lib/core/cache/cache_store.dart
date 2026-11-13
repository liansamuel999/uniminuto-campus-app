import 'package:hive_ce/hive.dart';

/// Envoltura mínima sobre una caja de Hive con marca de tiempo para aplicar vigencia (D-40).
class CacheStore {
  CacheStore(this._caja);

  final Box<dynamic> _caja;

  static const String _campoValor = 'valor';
  static const String _campoGuardadoEn = 'guardado_en';

  /// Guarda un valor serializable junto con la hora (UTC) en que se escribió.
  Future<void> guardar(String clave, Object? valor) {
    return _caja.put(clave, <String, Object?>{
      _campoValor: valor,
      _campoGuardadoEn: DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Devuelve el valor si existe y no supera [vigencia]; si venció, lo elimina.
  T? leer<T>(String clave, {Duration? vigencia}) {
    final registro = _caja.get(clave);
    if (registro is! Map) return null;

    if (vigencia != null) {
      final guardadoEn = DateTime.tryParse('${registro[_campoGuardadoEn]}');
      if (guardadoEn == null || DateTime.now().toUtc().difference(guardadoEn) > vigencia) {
        // Se ignora el borrado: el dato vencido no se devuelve igualmente.
        _caja.delete(clave);
        return null;
      }
    }

    final valor = registro[_campoValor];
    return valor is T ? valor : null;
  }

  /// Fecha (UTC) de la última escritura, o `null` si no hay dato.
  DateTime? fechaDe(String clave) {
    final registro = _caja.get(clave);
    if (registro is! Map) return null;
    return DateTime.tryParse('${registro[_campoGuardadoEn]}');
  }

  Future<void> borrar(String clave) => _caja.delete(clave);

  Future<void> limpiar() => _caja.clear();
}
