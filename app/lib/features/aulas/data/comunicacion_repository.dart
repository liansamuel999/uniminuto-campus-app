import 'package:cloud_firestore/cloud_firestore.dart';

/// Hilo de un foro de actividad (`foros/{foroId}/hilos`, D-47).
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

/// Mensaje dentro de un hilo (`foros/{foroId}/hilos/{hiloId}/mensajes`).
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

/// Anuncio institucional de un aula (`anuncios/{aulaId}/items`, D-48).
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

/// Repositorio de foros y anuncios en Cloud Firestore (D-41, D-47 y D-48).
///
/// Las reglas de seguridad autorizan por membresía del aula: el espejo
/// `aulas_index/{aulaId}` lo mantiene la API (semilla) y cada hilo/anuncio guarda `aula_id`.
class RepositorioComunicacion {
  RepositorioComunicacion({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _hilos(String foroId) =>
      _db.collection('foros').doc(foroId).collection('hilos');

  Stream<List<HiloForo>> hilos(String foroId) => _hilos(foroId)
      .orderBy('creado_en', descending: true)
      .snapshots()
      .map((snapshot) => [
            for (final doc in snapshot.docs)
              HiloForo(
                id: doc.id,
                titulo: '${doc.data()['titulo'] ?? 'Sin título'}',
                autorNombre: '${doc.data()['autor_nombre'] ?? 'Participante'}',
                autorUid: '${doc.data()['autor_uid'] ?? ''}',
                creadoEn: _fecha(doc.data()['creado_en']),
              ),
          ]);

  Future<void> crearHilo({
    required String foroId,
    required String aulaId,
    required String autorUid,
    required String autorNombre,
    required String titulo,
  }) async {
    await _hilos(foroId).add({
      'titulo': titulo,
      'autor_uid': autorUid,
      'autor_nombre': autorNombre,
      'aula_id': aulaId,
      'foro_id': foroId,
      'creado_en': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<MensajeForo>> mensajes(String foroId, String hiloId) => _hilos(foroId)
      .doc(hiloId)
      .collection('mensajes')
      .orderBy('creado_en')
      .snapshots()
      .map((snapshot) => [
            for (final doc in snapshot.docs)
              MensajeForo(
                id: doc.id,
                texto: '${doc.data()['texto'] ?? ''}',
                autorNombre: '${doc.data()['autor_nombre'] ?? 'Participante'}',
                creadoEn: _fecha(doc.data()['creado_en']),
              ),
          ]);

  Future<void> enviarMensaje({
    required String foroId,
    required String hiloId,
    required String aulaId,
    required String autorUid,
    required String autorNombre,
    required String texto,
  }) async {
    await _hilos(foroId).doc(hiloId).collection('mensajes').add({
      'texto': texto,
      'autor_uid': autorUid,
      'autor_nombre': autorNombre,
      'aula_id': aulaId,
      'creado_en': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AnuncioAula>> anuncios(String aulaId) => _db
      .collection('anuncios')
      .doc(aulaId)
      .collection('items')
      .orderBy('creado_en', descending: true)
      .snapshots()
      .map((snapshot) => [
            for (final doc in snapshot.docs)
              AnuncioAula(
                id: doc.id,
                titulo: '${doc.data()['titulo'] ?? 'Anuncio'}',
                cuerpo: '${doc.data()['cuerpo'] ?? ''}',
                importante: doc.data()['importante'] == true,
                autorNombre: '${doc.data()['autor_nombre'] ?? 'Docente'}',
                creadoEn: _fecha(doc.data()['creado_en']),
              ),
          ]);

  /// Publica un anuncio y devuelve su id para, si es importante, replicarlo por correo (D-48).
  Future<String> publicarAnuncio({
    required String aulaId,
    required String autorUid,
    required String autorNombre,
    required String titulo,
    required String cuerpo,
    required bool importante,
  }) async {
    final referencia = await _db.collection('anuncios').doc(aulaId).collection('items').add({
      'titulo': titulo,
      'cuerpo': cuerpo,
      'importante': importante,
      'autor_uid': autorUid,
      'autor_nombre': autorNombre,
      'creado_en': FieldValue.serverTimestamp(),
    });
    return referencia.id;
  }

  static DateTime? _fecha(dynamic valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is String) return DateTime.tryParse(valor);
    return null;
  }
}
