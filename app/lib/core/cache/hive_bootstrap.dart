import 'package:hive_ce_flutter/hive_flutter.dart';

/// Cajas de caché local por dominio (§4.1, D-40).
const List<String> nombresDeCajas = <String>[
  'carnet',
  'horario',
  'notas',
  'validador_jti',
  'validador_eventos',
  'config',
];

/// Abre Hive una sola vez al arrancar la app.
///
/// En Web `initFlutter` usa IndexedDB; en Android/iOS usa el directorio de documentos.
Future<void> abrirCacheLocal() async {
  await Hive.initFlutter();
  await Future.wait(nombresDeCajas.map((nombre) => Hive.openBox<dynamic>(nombre)));
}

/// Cierra las cajas (útil en pruebas y en el cierre ordenado).
Future<void> cerrarCacheLocal() async {
  await Hive.close();
}
