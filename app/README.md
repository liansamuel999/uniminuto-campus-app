# `app/` — cliente Flutter

Aplicación única para APK Android y Web/PWA (§1, §7.5). Organización por *features* y `core`
tal como fija §7.1.

```
lib/
├── main.dart                 arranque: Hive, Firebase opcional, ProviderScope
├── app.dart                  MaterialApp.router + PhoneFrame
├── core/
│   ├── api/                  ApiClient (dio + ID Token + errores del contrato)
│   ├── cache/                Hive (cajas por dominio) y CacheStore con vigencia
│   ├── config/               AppConfig (dart-define), Firebase (opcional en 0B)
│   ├── router/               go_router, ShellRoute y barra inferior por rol
│   ├── session/              sesión y rol activo (solo UI, D-21)
│   ├── theme/                Material 3, azul institucional neutro
│   └── widgets/              PhoneFrame, aviso de muestra, pantallas "próximamente"
└── features/
    ├── auth/                 login (Fase 1 conecta Firebase)
    ├── home/                 inicio con accesos por módulo
    ├── carnet/               placeholder (Fase 2)
    └── perfil/               sesión, roles y aviso de datos
```

## Ejecutar

```powershell
flutter pub get
flutter run --dart-define-from-file=env/dev.json        # Android/emulador
flutter run -d chrome --dart-define-from-file=env/dev.json
flutter analyze
flutter test
```

## Notas de la Fase 0B

- `lib/core/config/firebase_options.dart` es un **archivo de ejemplo** (`kFirebaseConfigurado ==
  false`). La Fase 1 lo reemplaza con `flutterfire configure` y el login real empieza a funcionar.
  Mientras tanto el login ofrece "Entrar en modo muestra" para verificar la navegación.
- Las dependencias de QR, escáner y claves (`qr_flutter`, `barcode_widget`, `mobile_scanner`,
  `dart_jsonwebtoken`, `flutter_secure_storage`) se añaden en la Fase 2, cuando se usan.
- `env/dev.json` y `env/prod.json` no contienen secretos: solo `API_BASE_URL` y `ENTORNO` (§7.2).
- En Web, `PhoneFrame` limita la app a 430 px y simula un teléfono en pantallas > 600 px.
