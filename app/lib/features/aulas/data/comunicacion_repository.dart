import '../../../core/api/api_client.dart';

/// Hilo de un foro de actividad (servido por la API sobre Firestore, D-78).
class HiloForo {
  const HiloForo({
    required this.id,
    required this.titulo,
    required this.autorNombre,
    required this.autorUid,
    this.creadoEn,
  });

  final String id;
  final String titulo;
  final String autorNombre;
  final String autorUid;
  final DateTime? creadoEn;
}

/// Mensaje dentro de un hilo.
class MensajeForo {
  const MensajeForo({
    required this.id,
    required this.texto,
    required this.autorNombre,
    this.creadoEn,
  });

  final String id;
  final String texto;
  final String autorNombre;
  final DateTime? creadoEn;
}

/// Anuncio institucional de un aula.
class AnuncioAula {
  const AnuncioAula({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.importante,
    required this.autorNombre,
    this.creadoEn,
  });

  final String id;
  final String titulo;
  final String cuerpo;
  final bool importante;
  final String autorNombre;
  final DateTime? creadoEn;
}

/// Repositorio de foros y anuncios.
///
/// La API valida la pertenencia al aula y lee/escribe Firestore con el Admin SDK (D-78); así las
/// consultas de lista funcionan sin depender de reglas de seguridad que el motor no admite para
/// queries con `get()`. Las pantallas refrescan al abrir, al deslizar y después de escribir.
class RepositorioComunicacion {
  RepositorioComunicacion(this._api);

  final ApiClient _api;

  static List<Map<String, dynamic>> _mapas(List<dynamic> datos) =>
      datos.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();

  static DateTime? _fecha(dynamic valor) => DateTime.tryParse('$valor');

  Future<List<HiloForo>> hilos(String foroId) async {
    final datos = await _api.getList('/foros/$foroId/hilos');
    return _mapas(datos)
        .map((fila) => HiloForo(
              id: '${fila['id']}',
              titulo: '${fila['titulo']}',
              autorNombre: '${fila['autorNombre'] ?? 'Participante'}',
              autorUid: '${fila['autorUid'] ?? ''}',
              creadoEn: _fecha(fila['creadoEn']),
            ))
        .toList();
  }

  Future<void> crearHilo({
    required String foroId,
    required String aulaId,
    required String autorUid,
    required String autorNombre,
    required String titulo,
  }) async {
    await _api.postJson('/foros/$foroId/hilos', cuerpo: {'titulo': titulo});
  }

  Future<List<MensajeForo>> mensajes(String foroId, String hiloId) async {
    final datos = await _api.getList('/foros/$foroId/hilos/$hiloId/mensajes');
    return _mapas(datos)
        .map((fila) => MensajeForo(
              id: '${fila['id']}',
              texto: '${fila['texto']}',
              autorNombre: '${fila['autorNombre'] ?? 'Participante'}',
              creadoEn: _fecha(fila['creadoEn']),
            ))
        .toList();
  }

  Future<void> enviarMensaje({
    required String foroId,
    required String hiloId,
    required String aulaId,
    required String autorUid,
    required String autorNombre,
    required String texto,
  }) async {
    await _api.postJson('/foros/$foroId/hilos/$hiloId/mensajes', cuerpo: {'texto': texto});
  }

  Future<List<AnuncioAula>> anuncios(String aulaId) async {
    final datos = await _api.getList('/aulas/$aulaId/anuncios');
    return _mapas(datos)
        .map((fila) => AnuncioAula(
              id: '${fila['id']}',
              titulo: '${fila['titulo']}',
              cuerpo: '${fila['cuerpo']}',
              importante: fila['importante'] == true,
              autorNombre: '${fila['autorNombre'] ?? 'Docente'}',
              creadoEn: _fecha(fila['creadoEn']),
            ))
        .toList();
  }

  /// Publica un anuncio y devuelve su id para, si es importante, replicarlo por correo (D-48).
  Future<String> publicarAnuncio({
    required String aulaId,
    required String autorUid,
    required String autorNombre,
    required String titulo,
    required String cuerpo,
    required bool importante,
  }) async {
    final respuesta = await _api.postJson('/aulas/$aulaId/anuncios', cuerpo: {
      'titulo': titulo,
      'cuerpo': cuerpo,
      'importante': importante,
    });
    return '${respuesta['id']}';
  }
}
