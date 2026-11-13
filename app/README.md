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

## Notas de la Fase 1

- `lib/firebase_options.dart` es el archivo **real** generado por `flutterfire configure` para el
  proyecto `uniminuto-campus-app` (identificadores públicos, sin secretos). `android/app/
  google-services.json` también está versionado por la misma razón.
- El login usa Firebase Authentication (correo + contraseña) y el router espera la sesión:
  `/cargando` → `/login` o `/inicio`. Los roles se leen de los *custom claims* y se contrastan con
  `GET /api/v1/mi-perfil`.
- La semilla crea las cuentas de demostración (`Demo1234*`). En `ENTORNO=dev` el formulario llega
  precargado y muestra el recordatorio de cuentas (D-62).
- El cambio de contraseña pide la contraseña actual (reautenticación) antes de actualizarla.
