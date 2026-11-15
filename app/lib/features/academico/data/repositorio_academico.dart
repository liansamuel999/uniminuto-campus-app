import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/cache/cache_store.dart';
import 'package:hive_ce/hive.dart';

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

  Future<List<dynamic>> aulas() => _api.getList('/aulas');

  Future<List<dynamic>> proximasActividades() => _api.getList('/mis-actividades/proximas');

  Future<List<dynamic>> participantes(String aulaId) =>
      _api.getList('/aulas/$aulaId/participantes');

  Future<List<dynamic>> misCalificaciones(String aulaId) =>
      _api.getList('/aulas/$aulaId/mis-calificaciones');

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

  /// URL firmada (15 min) para leer un archivo del datalake por su clave.
  Future<String> urlDeObjeto(String objetoKey) async {
    final datos = await _api.getJson(
      '/archivos/por-clave/url',
      parametros: {'objetoKey': objetoKey},
    );
    return '${datos['url']}';
  }

  /// Sube un archivo al datalake con la URL prefirmada y devuelve su clave.
  Future<Map<String, dynamic>> subirArchivo({
    required String contexto,
    required String nombre,
    required String mime,
    required Uint8List bytes,
  }) async {
    final firma = await _api.postJson('/archivos/subida', cuerpo: {
      'contexto': contexto,
      'nombre': nombre,
      'mime': mime,
      'tamano': bytes.length,
    });
    await _api.dio.put<dynamic>(
      '${firma['urlPut']}',
      data: bytes,
      options: Options(headers: {'Content-Type': mime}),
    );
    return firma;
  }

  // ── Edición del aula por el docente ─────────────────────────────────────
  Future<void> editarAula(String aulaId, {String? nombre, String? descripcion}) =>
      _api.putJson('/aulas/$aulaId', cuerpo: {
        if (nombre != null) 'nombre': nombre,
        if (descripcion != null) 'descripcion': descripcion,
      });

  Future<Map<String, dynamic>> crearUnidad(String aulaId, {required String titulo}) =>
      _api.postJson('/aulas/$aulaId/unidades', cuerpo: {'titulo': titulo});

  Future<void> editarUnidad(String unidadId, {String? titulo}) =>
      _api.putJson('/unidades/$unidadId', cuerpo: {if (titulo != null) 'titulo': titulo});

  Future<void> eliminarUnidad(String unidadId) async {
    await _api.deleteJson('/unidades/$unidadId');
  }

  Future<Map<String, dynamic>> crearContenido(
    String unidadId, {
    required String tipo,
    required String titulo,
    String? descripcion,
    String? objetoKey,
    String? urlExterna,
    String? mime,
    int? tamano,
  }) =>
      _api.postJson('/unidades/$unidadId/contenidos', cuerpo: {
        'tipo': tipo,
        'titulo': titulo,
        if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
        if (objetoKey != null) 'objetoKey': objetoKey,
        if (urlExterna != null) 'urlExterna': urlExterna,
        if (mime != null) 'mime': mime,
        if (tamano != null) 'tamano': tamano,
      });

  Future<void> eliminarContenido(String contenidoId) async {
    await _api.deleteJson('/contenidos/$contenidoId');
  }

  Future<Map<String, dynamic>> crearActividad(
    String unidadId, {
    required String tipo,
    required String titulo,
    String? instrucciones,
    DateTime? cierraEn,
    required int corte,
    required double peso,
    double? notaMaxima,
    List<String>? formatosPermitidos,
  }) =>
      _api.postJson('/unidades/$unidadId/actividades', cuerpo: {
        'tipo': tipo,
        'titulo': titulo,
        if (instrucciones != null && instrucciones.isNotEmpty) 'instrucciones': instrucciones,
        if (cierraEn != null) 'cierraEn': cierraEn.toUtc().toIso8601String(),
        'corte': corte,
        'peso': peso,
        if (notaMaxima != null) 'notaMaxima': notaMaxima,
        if (formatosPermitidos != null && formatosPermitidos.isNotEmpty)
          'formatosPermitidos': formatosPermitidos,
      });

  Future<void> editarActividad(
    String actividadId, {
    String? titulo,
    String? instrucciones,
    DateTime? cierraEn,
    double? peso,
    double? notaMaxima,
    List<String>? formatosPermitidos,
  }) =>
      _api.putJson('/actividades/$actividadId', cuerpo: {
        if (titulo != null) 'titulo': titulo,
        if (instrucciones != null) 'instrucciones': instrucciones,
        if (cierraEn != null) 'cierraEn': cierraEn.toUtc().toIso8601String(),
        if (peso != null) 'peso': peso,
        if (notaMaxima != null) 'notaMaxima': notaMaxima,
        if (formatosPermitidos != null && formatosPermitidos.isNotEmpty)
          'formatosPermitidos': formatosPermitidos,
      });

  Future<Map<String, dynamic>?> miEntrega(String actividadId) async {
    try {
      return await _api.getJson('/actividades/$actividadId/mi-entrega');
    } on ApiException catch (error) {
      if (error.estado == 404 || error.codigo == 'NO_ENCONTRADO') return null;
      rethrow;
    }
  }

  Future<void> eliminarActividad(String actividadId) async {
    await _api.deleteJson('/actividades/$actividadId');
  }

  List<dynamic>? _leerCache(CacheStore cache, String clave) {
    final valor = cache.leer<List<dynamic>>(clave, vigencia: vigenciaAcademica);
    return valor;
  }
}
