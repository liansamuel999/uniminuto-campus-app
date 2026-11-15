import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../../core/api/api_client.dart';
import '../../../core/security/device_keys.dart';
import '../domain/carnet.dart';

/// Acceso al carnet: API + caché local para funcionar sin red (§2.2, §6.1).
class CarnetRepository {
  CarnetRepository({
    required ApiClient api,
    required Box<dynamic> cache,
    required AlmacenClavesDispositivo almacen,
  })  : _api = api,
        _cache = cache,
        _almacen = almacen;

  static const String _claveResumen = 'resumen';

  final ApiClient _api;
  final Box<dynamic> _cache;
  final AlmacenClavesDispositivo _almacen;

  /// Última copia guardada (funciona sin conexión).
  ResumenCarnet? cargarLocal() {
    final crudo = _cache.get(_claveResumen);
    if (crudo is! Map) return null;
    try {
      return ResumenCarnet.fromJson(Map<String, dynamic>.from(crudo));
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardar(ResumenCarnet resumen) {
    return _cache.put(_claveResumen, jsonDecode(jsonEncode(resumen.toJson())) as Map<dynamic, dynamic>);
  }

  /// Consulta `/carnet/mio`; devuelve `null` si el usuario no tiene carnet (404).
  Future<ResumenCarnet?> sincronizar() async {
    try {
      final json = await _api.getJson('/carnet/mio');
      final resumen = ResumenCarnet.fromJson(json);
      await _guardar(resumen);
      return resumen;
    } on ApiException catch (error) {
      if (error.estado == 404) return null;
      rethrow;
    }
  }

  Future<ClaveDispositivo?> claveGuardada() => _almacen.cargar();

  /// Genera el par del dispositivo y lo vincula (§6.1).
  Future<ResumenCarnet> vincular(String nombreDispositivo) async {
    final clave = await _almacen.generar();
    final json = await _api.postJson('/dispositivos', cuerpo: {
      'nombreDispositivo': nombreDispositivo,
      'clavePublicaJwk': clave.clavePublicaJwk,
    });
    final resumen = ResumenCarnet.fromJson(json);
    await _guardar(resumen);
    return resumen;
  }

  /// Renueva el certificado del dispositivo activo.
  Future<ResumenCarnet> renovar() async {
    final json = await _api.postJson('/dispositivos/renovar-certificado');
    final resumen = ResumenCarnet.fromJson(json);
    await _guardar(resumen);
    return resumen;
  }

  /// Revoca el dispositivo y borra la clave local.
  Future<void> revocar() async {
    final resumen = cargarLocal();
    final dispositivoId = resumen?.dispositivoId;
    if (dispositivoId != null) {
      await _api.deleteJson('/dispositivos/$dispositivoId');
    }
    await _almacen.borrar();
    await _cache.delete(_claveResumen);
  }
}
