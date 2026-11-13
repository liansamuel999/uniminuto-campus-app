import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';

/// Marcador de configuración de Firebase.
///
/// La Fase 1 ejecuta `flutterfire configure` (genera `firebase_options.dart` con los
/// identificadores públicos) y luego cambia este valor a `true`.
const bool kFirebaseConfigurado = false;

/// Indica si Firebase se inicializó correctamente en esta ejecución.
final firebaseDisponibleProvider = Provider<bool>((ref) => false);

/// Inicializa Firebase solo si `firebase_options.dart` fue generado por FlutterFire (Fase 1).
///
/// En la Fase 0B el archivo sigue siendo el de ejemplo (`kFirebaseConfigurado == false`), así que
/// la app arranca sin Firebase y el login muestra el aviso correspondiente.
Future<bool> inicializarFirebase() async {
  if (!kFirebaseConfigurado) return false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    return true;
  } catch (_) {
    return false;
  }
}
