import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cola local de entregas para preparar tareas sin conexión (§6.2).
class ColaEntregas {
  ColaEntregas(this._api, this._caja);

  final ApiClient _api;
  final Box<dynamic> _caja;

  static const String _clave = 'pendientes';

  List<Map<String, dynamic>> pendientes() {
    final valor = _caja.get(_clave);
    if (valor is! List) return const [];
    return valor.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  /// Guarda la entrega con su UUID de idempotencia generado en el cliente.
  Future<void> encolar({
    required String entregaId,
    required String actividadId,
    required String texto,
    required DateTime creadaEnCliente,
    List<Map<String, dynamic>> adjuntos = const [],
  }) async {
    final lista = pendientes()
      ..removeWhere((item) => item['entregaId'] == entregaId)
      ..add({
        'entregaId': entregaId,
        'actividadId': actividadId,
        'texto': texto,
        'creadaEnCliente': creadaEnCliente.toUtc().toIso8601String(),
        'adjuntos': adjuntos,
      });
    await _caja.put(_clave, lista);
  }

  Future<void> quitar(String entregaId) async {
    final lista = pendientes()..removeWhere((item) => item['entregaId'] == entregaId);
    await _caja.put(_clave, lista);
  }

  /// Intenta enviar toda la cola; conserva solo las que fallan por red.
  Future<int> sincronizar() async {
    var enviadas = 0;
    for (final entrega in pendientes()) {
      try {
        await _api.postJson('/entregas', cuerpo: {
          'entregaId': entrega['entregaId'],
          'actividadId': entrega['actividadId'],
          'texto': entrega['texto'],
          'creadaEnCliente': entrega['creadaEnCliente'],
          'adjuntos': entrega['adjuntos'] ?? const [],
        });
        await quitar('${entrega['entregaId']}');
        enviadas += 1;
      } on ApiException catch (error) {
        if (error.esSinRed) break;
        // Rechazo definitivo del servidor: se descarta para no bloquear la cola.
        await quitar('${entrega['entregaId']}');
      }
    }
    return enviadas;
  }
}

final colaEntregasProvider = Provider<ColaEntregas>((ref) {
  return ColaEntregas(ref.watch(apiClientProvider), Hive.box<dynamic>('entregas'));
});

/// Identificador UUID v4 local para la entrega (idempotencia).
///
/// Se usa el paquete `uuid`: el generador casero anterior podía producir cadenas de longitud
/// incorrecta (XOR con valores > 255) y la API respondía «Invalid UUID».
String nuevoUuid() => const Uuid().v4();

/// Para depuración: JSON de la cola.
String describirCola(ColaEntregas cola) => jsonEncode(cola.pendientes());
