import 'package:campus_app/core/config/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión del error "No MaterialLocalizations found" en la pantalla de login:
/// `MaterialApp` con locale es_CO debe incluir los delegados globales.
void main() {
  testWidgets('los widgets de Material funcionan con locale es_CO', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: localeEspanol,
        supportedLocales: localesSoportados,
        localizationsDelegates: delegadosDeLocalizacion,
        home: const Scaffold(
          body: TextField(decoration: InputDecoration(labelText: 'Correo institucional')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
