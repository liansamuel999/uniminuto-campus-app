import 'dart:io';

import 'package:campus_app/core/cache/cache_store.dart';
import 'package:campus_app/core/theme/app_theme.dart';
import 'package:campus_app/core/widgets/phone_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  group('PhoneFrame (§7.5, D-39)', () {
    testWidgets('en pantallas anchas el contenido se limita a 430 px', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clave = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.claro(),
          home: PhoneFrame(
            forzarWeb: true,
            child: SizedBox(key: clave, width: 1200, height: 900),
          ),
        ),
      );

      // El borde de 1 px a cada lado deja 428 px útiles dentro del marco de 430.
      expect(tester.getSize(find.byKey(clave)).width, closeTo(430, 4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('en pantalla angosta el contenido ocupa todo el ancho', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clave = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.claro(),
          home: PhoneFrame(
            forzarWeb: true,
            child: SizedBox(key: clave, width: 400, height: 800),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(clave)).width, 400);
    });

    testWidgets('en móvil (no web) no dibuja marco', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clave = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.claro(),
          home: PhoneFrame(
            forzarWeb: false,
            child: SizedBox(key: clave, width: 400, height: 800),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(clave)).width, 400);
    });
  });

  group('CacheStore (D-40)', () {
    setUpAll(() async {
      Hive.init('${Directory.systemTemp.path}${Platform.pathSeparator}hive_campus_test');
    });

    tearDownAll(() async {
      await Hive.close();
    });

    test('guarda, lee y descarta valores vencidos', () async {
      final caja = await Hive.openBox<dynamic>('pruebas_cache');
      final store = CacheStore(caja);

      await store.guardar('horario', {'clave': 'valor'});
      expect(store.leer<Map>('horario'), isNotNull);
      expect(store.fechaDe('horario'), isNotNull);

      await store.guardar('viejo', 'dato');
      expect(store.leer<String>('viejo', vigencia: Duration.zero), isNull);
      expect(store.leer<String>('viejo'), isNull);

      await caja.deleteFromDisk();
    });
  });
}
