import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Marcador temporal de la Fase 0B.
///
/// `false` indica que este archivo **todavía es el de ejemplo** y que Firebase aún no se ha
/// configurado. La Fase 1 lo reemplaza ejecutando `flutterfire configure`, que genera el archivo
/// real con los identificadores públicos del proyecto (no contiene secretos) y lo deja con
/// `true`.
const bool kFirebaseConfigurado = false;

/// Opciones de ejemplo. **No son credenciales reales.**
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'PENDIENTE_DE_FLUTTERFIRE_CONFIGURE',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'uniminuto-campus-app',
    authDomain: 'uniminuto-campus-app.firebaseapp.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PENDIENTE_DE_FLUTTERFIRE_CONFIGURE',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'uniminuto-campus-app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'PENDIENTE_DE_FLUTTERFIRE_CONFIGURE',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'uniminuto-campus-app',
    iosBundleId: 'co.edu.uniminuto.demo.campusApp',
  );
}
