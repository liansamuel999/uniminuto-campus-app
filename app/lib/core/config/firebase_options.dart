import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// ARCHIVO DE EJEMPLO (Fase 0B).
///
/// La Fase 1 lo reemplaza por el que genera `flutterfire configure`; este archivo se puede
/// sobrescribir sin tocar el resto del código. El marcador de "Firebase configurado" vive en
/// `firebase_bootstrap.dart`, no aquí.
///
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
