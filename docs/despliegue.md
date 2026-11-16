# Despliegue de la demo — Uniminuto Campus App

Pasos para publicar la muestra (§7.4 y §7.5 de [`arquitectura.md`](arquitectura.md)). El despliegue
público requiere cuentas propias; este documento y los archivos del repositorio lo dejan preparado.

## 0. Piezas a publicar

| Pieza | Servicio | Archivo de apoyo |
|---|---|---|
| Base de datos | CockroachDB Cloud (capa gratuita) | `infra/migrations/` + `npm run db:seed` |
| Datalake de archivos | Cloudflare R2 (S3-compatible) o MinIO local | `infra/r2/cors.json` |
| API | Render (servicio web Node) | [`../render.yaml`](../render.yaml) |
| App web (PWA) | Firebase Hosting o GitHub Pages | `firebase.json`, `app/env/prod.json` |
| APK Android | Distribución manual | `flutter build apk --release` |

## 1. Base de datos (CockroachDB Cloud)

1. Crear un clúster gratuito y la base de datos `campus`.
2. Crear un usuario SQL para la API y copiar la cadena de conexión TLS a `DATABASE_URL`.
3. Desde `api/`, con un `.env` temporal apuntando a ese clúster:
   ```bash
   npm ci
   npm run db:migrate      # migraciones 0000–0008
   npm run db:seed         # usuarios y campus ficticios (idempotente)
   npm run rules:deploy    # reglas de Firestore (D-65)
   ```

## 2. Datalake (Cloudflare R2)

1. Crear el bucket **privado** `campus-app`.
2. Generar credenciales S3 de la cuenta (Access Key / Secret).
3. Aplicar CORS con [`../infra/r2/cors.json`](../infra/r2/cors.json) (ajusta el dominio de Hosting):
   ```bash
   npx wrangler r2 bucket cors put campus-app --file infra/r2/cors.json
   ```
4. Variables para la API: `S3_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com`,
   `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET=campus-app`, `S3_REGION=auto`.

En desarrollo se usa MinIO con las mismas variables (`npm run infra:minio`).

## 3. API en Render

1. En Render: **New → Blueprint** y seleccionar el repositorio (usa [`../render.yaml`](../render.yaml)).
2. Cargar las variables marcadas como secretas (el blueprint no las versiona):

   | Variable | Valor |
   |---|---|
   | `DATABASE_URL` | Cadena TLS de CockroachDB Cloud |
   | `FIREBASE_SERVICE_ACCOUNT` | JSON de la cuenta de servicio **en una línea** |
   | `INSTITUTION_PRIVATE_KEY` | JWK privado ES256 **en una línea** (D-60) |
   | `INSTITUTION_KID` | `inst-2026-11-d93e89` (o el vigente) |
   | `CORS_ORIGINS` | `https://<proyecto>.web.app,https://<proyecto>.firebaseapp.com` |
   | `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` | Credenciales de R2 |
   | `S3_BUCKET`, `S3_REGION` | `campus-app`, `auto` |

   `ENTORNO=prod` es obligatorio: la API **rechaza** `AUTH_DEV_SECRET` en producción y exige
   cuenta de servicio y clave institucional.
3. Verificar `https://<servicio>.onrender.com/health` → `{"estado":"ok","db":"ok","storage":"ok"}`.
4. En Render, `PORT` lo inyecta la plataforma; no se define a mano.

> El plan gratuito de Render duerme el servicio tras inactividad: la primera petición puede tardar
> unos segundos. Para la demo, entrar una vez antes de mostrarla.

## 4. App web en Firebase Hosting

1. Ajustar `app/env/prod.json` con la URL real de la API:
   ```json
   { "API_BASE_URL": "https://<servicio>.onrender.com/api/v1", "ENTORNO": "prod" }
   ```
2. Compilar:
   ```bash
   cd app
   flutter build web --release --dart-define-from-file=env/prod.json
   ```
3. Publicar con la CLI (sin instalación global):
   ```bash
   npx firebase-tools login
   npx firebase-tools deploy --only hosting --config firebase.json
   ```
   El [`firebase.json`](../firebase.json) de la raíz ya apunta a `app/build/web`, reescribe todas las
   rutas a `index.html` y `.firebaserc` fija el proyecto `uniminuto-campus-app`.
4. En Firebase Console → Authentication → **Dominios autorizados**, añadir
   `<proyecto>.web.app` y `<proyecto>.firebaseapp.com`.
5. Añadir esos dominios a `CORS_ORIGINS` de la API y redeployar Render.
6. Alternativa GitHub Pages: `flutter build web --release --base-href "/<repo>/"` y publicar
   `build/web` en `gh-pages`; añadir `<usuario>.github.io` a dominios autorizados y `CORS_ORIGINS`.
   Como Pages no reescribe rutas, esa variante requiere `#` en las URL de go_router.

## 5. APK Android

Requisito de toolchain: Android SDK, **JDK 17–21**, el **SDK de Flutter fijado por el proyecto**
(3.41.9) y el **NDK 28.2.13676358** (Flutter 3.41.9 lo exige por defecto). En la PC de la demo
quedaron instalados Temurin 21, Flutter 3.41.9 en local y el NDK con `sdkmanager`, porque el
Flutter 3.50 del sistema exige Gradle 9.5/AGP 9 y el wrapper del proyecto es 8.14. El plugin Kotlin
se fija en **2.4.20** (`android/build.gradle.kts` define `kotlin_version`), las librerías de Firebase
compilan con metadata 2.4 y `jvmTarget` usa el DSL `compilerOptions`.

```powershell
flutter config --jdk-dir="C:\Users\lians\jdks\temurin21\jdk-21.0.13+9"
"C:\Users\lians\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" "ndk;28.2.13676358"
```

```bash
cd app
# Con el SDK fijado del proyecto:
C:\Users\lians\flutter-3.41.9\flutter\bin\flutter.bat build apk --release --dart-define-from-file=env/prod.json
# Salida: build/app/outputs/flutter-apk/app-release.apk
```

El APK se entrega para instalación manual (sin Google Play). Si `env/prod.json` todavía tiene la URL
de ejemplo, el APK no podrá autenticarse: recompile después de apuntar `API_BASE_URL` a la API real.
La firma es de depuración/release por defecto del proyecto de muestra; no se usa para producción.

## 6. Verificación post-despliegue

- [ ] `/health` de la API responde `estado: ok`, `db: ok`, `storage: ok`.
- [ ] La URL de Hosting abre en el navegador del teléfono con proporciones de teléfono (marco de 430 px).
- [ ] Login con `juan.rojas@demo.uniminuto.test / Demo1234*`.
- [ ] Carnet y QR: el validador acepta el QR (requiere HTTPS).
- [ ] Docente publica anuncio importante → estudiante lo ve en la bandeja simulada.
- [ ] Docente califica una entrega → estudiante ve la nota en **Mis notas**.
- [ ] Subida de un archivo a una entrega (usa R2/MinIO con URL prefirmada).
- [ ] Panel administrativo por rol y auditoría con al menos un evento.
- [ ] APK instalado en un teléfono abre la app y apunta a la API desplegada.

## 7. Secretos y rotación

- `api/.env`, `api/config/`, `infra/keys/` y el JWK privado **nunca** van al repositorio.
- En Render, el JSON de Firebase y el JWK institucional se cargan como variables de entorno.
- Si se rota la clave institucional, regenerar el par (`node infra/scripts/generate-keys.mjs`),
  volver a sembrar/emitir certificados y actualizar el JWKS público de la app (`app/assets/keys/`).
- Si se rota la cuenta de servicio de Firebase, actualizar la variable en Render y redeployar.
