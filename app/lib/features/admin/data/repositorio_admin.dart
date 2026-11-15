import '../../../core/api/api_client.dart';

/// Acceso a los endpoints administrativos de la Fase 5 (académico, espacios, incidencias y auditoría).
class RepositorioAdmin {
  RepositorioAdmin(this._api);

  final ApiClient _api;

  // ── Administración académica ────────────────────────────────────────────
  Future<List<dynamic>> periodos() => _api.getList('/periodos');

  Future<Map<String, dynamic>> crearPeriodo(Map<String, Object?> datos) =>
      _api.postJson('/periodos', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarPeriodo(String id, Map<String, Object?> datos) =>
      _api.putJson('/periodos/$id', cuerpo: datos);

  Future<void> eliminarPeriodo(String id) async {
    await _api.deleteJson('/periodos/$id');
  }

  Future<List<dynamic>> asignaturas() => _api.getList('/asignaturas');

  Future<Map<String, dynamic>> crearAsignatura(Map<String, Object?> datos) =>
      _api.postJson('/asignaturas', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarAsignatura(String id, Map<String, Object?> datos) =>
      _api.putJson('/asignaturas/$id', cuerpo: datos);

  Future<void> eliminarAsignatura(String id) async {
    await _api.deleteJson('/asignaturas/$id');
  }

  Future<List<dynamic>> grupos({String? periodoId, String? asignaturaId}) {
    final parametros = <String>[
      if (periodoId != null) 'periodoId=$periodoId',
      if (asignaturaId != null) 'asignaturaId=$asignaturaId',
    ];
    return _api.getList('/grupos${parametros.isEmpty ? '' : '?${parametros.join('&')}'}');
  }

  Future<Map<String, dynamic>> crearGrupo(Map<String, Object?> datos) =>
      _api.postJson('/grupos', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarGrupo(String id, Map<String, Object?> datos) =>
      _api.putJson('/grupos/$id', cuerpo: datos);

  Future<void> eliminarGrupo(String id) async {
    await _api.deleteJson('/grupos/$id');
  }

  Future<List<dynamic>> inscripciones({String? grupoId}) => _api.getList(
        '/inscripciones${grupoId == null ? '' : '?grupoId=$grupoId'}',
      );

  Future<Map<String, dynamic>> crearInscripcion(Map<String, Object?> datos) =>
      _api.postJson('/inscripciones', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarInscripcion(String id, String estado) =>
      _api.putJson('/inscripciones/$id', cuerpo: {'estado': estado});

  Future<void> eliminarInscripcion(String id) async {
    await _api.deleteJson('/inscripciones/$id');
  }

  Future<List<dynamic>> usuarios(String rol) => _api.getList('/admin/usuarios?rol=$rol');

  // ── Catálogo de espacios y horarios ─────────────────────────────────────
  Future<List<dynamic>> edificios() => _api.getList('/espacios/edificios');

  Future<Map<String, dynamic>> crearEdificio(Map<String, Object?> datos) =>
      _api.postJson('/espacios/edificios', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarEdificio(String id, Map<String, Object?> datos) =>
      _api.putJson('/espacios/edificios/$id', cuerpo: datos);

  Future<void> eliminarEdificio(String id) async {
    await _api.deleteJson('/espacios/edificios/$id');
  }

  Future<List<dynamic>> pisos(String edificioId) =>
      _api.getList('/espacios/edificios/$edificioId/pisos');

  Future<Map<String, dynamic>> crearPiso(Map<String, Object?> datos) =>
      _api.postJson('/espacios/pisos', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarPiso(String id, Map<String, Object?> datos) =>
      _api.putJson('/espacios/pisos/$id', cuerpo: datos);

  Future<void> eliminarPiso(String id) async {
    await _api.deleteJson('/espacios/pisos/$id');
  }

  Future<List<dynamic>> salonesTodos() => _api.getList('/espacios/salones');

  Future<Map<String, dynamic>> crearSalon(Map<String, Object?> datos) =>
      _api.postJson('/espacios/salones', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarSalon(String id, Map<String, Object?> datos) =>
      _api.putJson('/espacios/salones/$id', cuerpo: datos);

  Future<void> eliminarSalon(String id) async {
    await _api.deleteJson('/espacios/salones/$id');
  }

  Future<List<dynamic>> horarios({String? grupoId, String? salonId}) {
    final parametros = <String>[
      if (grupoId != null) 'grupoId=$grupoId',
      if (salonId != null) 'salonId=$salonId',
    ];
    return _api.getList('/horarios${parametros.isEmpty ? '' : '?${parametros.join('&')}'}');
  }

  Future<Map<String, dynamic>> crearHorario(Map<String, Object?> datos) =>
      _api.postJson('/horarios', cuerpo: datos);

  Future<Map<String, dynamic>> actualizarHorario(String id, Map<String, Object?> datos) =>
      _api.putJson('/horarios/$id', cuerpo: datos);

  Future<void> eliminarHorario(String id) async {
    await _api.deleteJson('/horarios/$id');
  }

  // ── Incidencias ─────────────────────────────────────────────────────────
  Future<List<dynamic>> incidenciasPropias() => _api.getList('/incidencias');

  Future<List<dynamic>> incidenciasSoporte({String? estado}) => _api.getList(
        '/incidencias${estado == null ? '' : '?estado=$estado'}',
      );

  Future<Map<String, dynamic>> reportarIncidencia(String descripcion) =>
      _api.postJson('/incidencias', cuerpo: {'descripcion': descripcion});

  Future<Map<String, dynamic>> actualizarIncidencia(
    String id, {
    required String estado,
    String? resolucion,
  }) =>
      _api.putJson('/incidencias/$id', cuerpo: {
        'estado': estado,
        if (resolucion != null && resolucion.trim().isNotEmpty) 'resolucion': resolucion.trim(),
      });

  // ── Auditoría ───────────────────────────────────────────────────────────
  Future<List<dynamic>> auditoria({
    String? desde,
    String? hasta,
    String? accion,
    String? antesDe,
    int limite = 50,
  }) {
    final parametros = <String>[
      'limite=$limite',
      if (desde != null) 'desde=${Uri.encodeQueryComponent(desde)}',
      if (hasta != null) 'hasta=${Uri.encodeQueryComponent(hasta)}',
      if (accion != null) 'accion=${Uri.encodeQueryComponent(accion)}',
      if (antesDe != null) 'antesDe=${Uri.encodeQueryComponent(antesDe)}',
    ];
    return _api.getList('/auditoria?${parametros.join('&')}');
  }

  Future<List<dynamic>> accionesAuditoria() => _api.getList('/auditoria/acciones');
}
