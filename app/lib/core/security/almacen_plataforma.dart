// Selecciona la implementación de almacén de claves y verificador ES256 según la plataforma.
///
// En Web usa WebCrypto no exportable + IndexedDB (D-29); en móvil, `flutter_secure_storage` y
// pointycastle (D-30).
export 'almacen_movil.dart' if (dart.library.js_interop) 'almacen_web.dart';
