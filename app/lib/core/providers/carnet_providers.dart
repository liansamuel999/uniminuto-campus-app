import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../features/carnet/data/carnet_repository.dart';
import '../../features/validador/data/caches.dart';
import '../../features/validador/domain/verificador.dart';
import '../security/almacen_plataforma.dart';
import '../security/claves_institucionales.dart';
import '../security/device_keys.dart';
import 'app_providers.dart';

/// Almacén de la clave del dispositivo (móvil o Web según la plataforma).
final almacenClavesProvider = Provider<AlmacenClavesDispositivo>((ref) => crearAlmacenDeClaves());

/// Verificador de firmas ES256 de la plataforma.
final verificadorEs256Provider = Provider<VerificadorEs256>((ref) => crearVerificadorEs256());

final carnetRepositoryProvider = Provider<CarnetRepository>((ref) {
  return CarnetRepository(
    api: ref.watch(apiClientProvider),
    cache: Hive.box<dynamic>('carnet'),
    almacen: ref.watch(almacenClavesProvider),
  );
});

/// JWKS institucional para el modo validador.
final clavesInstitucionalesProvider = FutureProvider<Map<String, Map<String, dynamic>>>(
  (ref) => cargarClavesInstitucionales(),
);

final cacheJtiProvider = Provider<CacheJti>((ref) => CacheJtiHive(Hive.box<dynamic>('validador_jti')));

final listaRevocadosProvider =
    Provider<ListaRevocadosHive>((ref) => ListaRevocadosHive(Hive.box<dynamic>('config')));

final colaEventosProvider = Provider<ColaEventos>((ref) => ColaEventos(Hive.box<dynamic>('validador_eventos')));

final historialValidacionesProvider =
    Provider<HistorialValidaciones>((ref) => HistorialValidaciones(Hive.box<dynamic>('validador_eventos')));

/// Verificador del modo validador con las 7 reglas de §6.1.
final verificadorCarnetProvider = FutureProvider<VerificadorCarnet>((ref) async {
  final claves = await ref.watch(clavesInstitucionalesProvider.future);
  return VerificadorCarnet(
    verificadorFirma: ref.watch(verificadorEs256Provider),
    clavesPorKid: claves,
    cacheJti: ref.watch(cacheJtiProvider),
    revocados: ref.watch(listaRevocadosProvider),
  );
});
