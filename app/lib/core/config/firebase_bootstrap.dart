import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';

/// `firebase_options.dart` ya fue generado por FlutterFire CLI (Fase 1).
const bool kFirebaseConfigurado = true;

/// Indica si Firebase se inicializó correctamente en esta ejecución.
final firebaseDisponibleProvider = Provider<bool>((ref) => false);

/// Inicializa Firebase con la configuración del proyecto `uniminuto-campus-app`.
Future<bool> inicializarFirebase() async {
  if (!kFirebaseConfigurado) return false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    return true;
  } catch (_) {
    return false;
  }
}
