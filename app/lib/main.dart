import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/cache/hive_bootstrap.dart';
import 'core/config/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Caché local (Hive) disponible desde el arranque: la usa el carnet offline en la Fase 2.
  await abrirCacheLocal();

  // Firebase es opcional en la Fase 0B: si `firebase_options.dart` aún no fue generado por
  // FlutterFire, la app arranca igual y el login lo indica.
  final firebaseListo = await inicializarFirebase();

  runApp(
    ProviderScope(
      overrides: [firebaseDisponibleProvider.overrideWithValue(firebaseListo)],
      child: const CampusApp(),
    ),
  );
}
