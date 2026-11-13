import 'package:flutter/foundation.dart';

/// Configuración de compilación pasada con `--dart-define-from-file` (§7.2).
/// Aquí no va ningún secreto: la app Flutter nunca contiene claves.
abstract final class AppConfig {
  /// URL base completa de la API, incluido el prefijo `/api/v1` (D-23).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  /// `dev` o `prod`.
  static const String entorno = String.fromEnvironment('ENTORNO', defaultValue: 'dev');

  static bool get esProduccion => entorno == 'prod';

  static const String nombreApp = 'Uniminuto Campus';
  static const String avisoMuestra = 'Proyecto de muestra – datos ficticios';

  /// Ancho máximo del marco tipo teléfono en pantallas anchas (§7.5).
  static const double anchoMovil = 430;
  static const double anchoRuptura = 600;

  /// true cuando la app se ejecuta en navegador.
  static bool get esWeb => kIsWeb;
}
