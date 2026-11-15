import 'package:hive_ce/hive.dart';

import '../../../core/api/api_client.dart';
import '../../../core/cache/cache_store.dart';

/// Vigencia de la caché de lectura académica (D-40).
const Duration vigenciaAcademica = Duration(hours: 12);

/// Lecturas académicas con caché local para funcionar sin conexión (§4.1, D-40):
/// horario y notas se guardan en sus cajas de Hive y se usan como respaldo sin red.
class RepositorioAcademico {
  RepositorioAcademico(this._api);

  final ApiClient _api;
  final CacheStore _cacheHorario = CacheStore(Hive.box<dynamic>('horario'));
  final CacheStore _cacheNotas = CacheStore(Hive.box<dynamic>('notas'));

  /// Horario semanal con ubicación del salón. Devuelve `(bloques, desdeCache)`.
  Future<(List<dynamic>, bool)> horario() async {
    try {
      final datos = await _api.getList('/mi-horario');
      await _cacheHorario.guardar('mi-horario', datos);
      return (datos, false);
    } on ApiException catch (error) {
      final cache = _leerCache(_cacheHorario, 'mi-horario');
      if (error.esSinRed && cache != null) return (cache, true);
      rethrow;
    }
  }

  /// Notas por asignatura, corte y actividad. Devuelve `(notas, desdeCache)`.
  Future<(List<dynamic>, bool)> notas() async {
    try {
      final datos = await _api.getList('/mis-notas');
      await _cacheNotas.guardar('mis-notas', datos);
      return (datos, false);
    } on ApiException catch (error) {
      final cache = _leerCache(_cacheNotas, 'mis-notas');
      if (error.esSinRed && cache != null) return (cache, true);
      rethrow;
    }
  }

  Future<List<dynamic>> asignaturas() => _api.getList('/mis-asignaturas');

  Future<Map<String, dynamic>> evaluarDocente({
    required String inscripcionId,
    required Map<String, int> respuestas,
    String? comentario,
  }) {
    return _api.postJson('/evaluaciones-docentes', cuerpo: {
      'inscripcionId': inscripcionId,
      'respuestas': respuestas,
      if (comentario != null && comentario.trim().isNotEmpty) 'comentario': comentario.trim(),
    });
  }

  Future<List<dynamic>> edificios() => _api.getList('/espacios/edificios');

  Future<List<dynamic>> pisos(String edificioId) =>
      _api.getList('/espacios/edificios/$edificioId/pisos');

  Future<List<dynamic>> salones(String pisoId) => _api.getList('/espacios/pisos/$pisoId/salones');

  List<dynamic>? _leerCache(CacheStore cache, String clave) {
    final valor = cache.leer<List<dynamic>>(clave, vigencia: vigenciaAcademica);
    return valor;
  }
}
