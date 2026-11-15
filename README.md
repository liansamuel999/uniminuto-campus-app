# Uniminuto Campus App — muestra universitaria

Aplicación Flutter (APK Android + Web/PWA) que unifica carnet digital con QR offline, módulo
académico y aulas virtuales de una sede ficticia de Uniminuto. **Proyecto de muestra: todos los
datos son ficticios y no existe integración real con Génesis, U-Wallet ni torniquetes.**

Documento de arquitectura (fuente de verdad): [`docs/arquitectura.md`](docs/arquitectura.md).
Decisiones no cubiertas por el documento: [`docs/DECISIONES.md`](docs/DECISIONES.md).

## Estructura del monorepo

| Carpeta | Contenido |
|---|---|
| `app/` | Cliente Flutter: `core` (api, caché, sync, seguridad) y *features* (`auth`, `carnet`, `validador`, `aulas`, `horarios`, `academico`, `perfil`, `admin`). |
| `api/` | Servicio Fastify + TypeScript: auth, carnet, acceso, aulas, actividades, calificaciones, horarios, espacios, archivos, auditoría, admin. |
| `infra/` | `docker-compose.yml` (CockroachDB nodo único + MinIO), migraciones SQL, scripts de claves y semilla, reglas de Firestore. |
| `docs/` | Arquitectura, decisiones y guía de demo. |

## Requisitos

- Flutter estable (probado con 3.41.9 / Dart 3.11.5)
- Node.js 22 LTS (probado con 22.23.5) y npm 10
- Docker Desktop para el datalake local (MinIO en 9000/9001)
- Proyecto Firebase con Authentication (correo/contraseña) y su cuenta de servicio en
  `api/config/firebase-service-account.json` (carpeta ignorada por git)
- CockroachDB Cloud (demo) **o** el CockroachDB local de `docker-compose` (desarrollo sin nube)

> **Entorno verificado el 2026-11-14.** La PC de la demo compila la app y pasa las pruebas con
> **Node 20.20.2** y **Flutter 3.50.0 / Dart 3.14.0**. El repositorio sigue fijado a Node 22
> (`.nvmrc`) y Flutter 3.41.9; con Flutter 3.50 `flutter analyze` solo añade los avisos
> `deprecated_member_use` del SDK al importar `package:flutter/material.dart`, sin errores de
> código (ver D-66 en [`docs/DECISIONES.md`](docs/DECISIONES.md)).

## Configuración de la API (`api/.env`)

Copiar `api/.env.example` a `api/.env` y ajustar:

| Variable | Valor esperado |
|---|---|
| `DATABASE_URL` | Cadena de CockroachDB Cloud con `sslmode=verify-full&sslrootcert=…` (en Windows, barras `/` en la ruta). Para trabajar solo en local: `postgresql://root@localhost:26257/campus?sslmode=disable`. |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | `./config/firebase-service-account.json` (relativa a `api/`). Alternativa para Render: `FIREBASE_SERVICE_ACCOUNT` con el JSON en una línea. |
| `AUTH_DEV_SECRET` | Solo dev: habilita `npm run token:dev`. Prohibido en producción. |
| `S3_*` | MinIO local (`minioadmin`/`minioadmin`, bucket `campus-app`) y, en la demo, Cloudflare R2. |

## Arranque rápido

```bash
# 1. Datalake local (MinIO). Crea el bucket privado `campus-app` automáticamente.
#    Con CockroachDB Cloud no hace falta el CockroachDB local; si lo quieres, usa `npm run infra:up`.
npm run infra:minio

# 2. Base de datos: aplica las migraciones sobre DATABASE_URL (idempotente).
npm run db:migrate

# 3. API
npm run api:dev

# 4. Verificación: {"estado":"ok","db":"ok","storage":"ok","version":"0.1.0"}
curl http://localhost:3000/health
```

> **Nota sobre MinIO (D-58).** MinIO retiró `minio/minio` y `minio/mc` de Docker Hub en septiembre de
> 2026. El `docker-compose.yml` usa la imagen de Bitnami —mismo servidor MinIO, misma API S3— fijada
> por tag inmutable, y crea el bucket con `MINIO_DEFAULT_BUCKETS`. El código no cambia: solo habla S3.

### Token de prueba (solo desarrollo)

Con el proyecto Firebase ya configurado, en desarrollo se aceptan **dos** tipos de token (D-59):
el ID Token real de Firebase y un token HS256 firmado con `AUTH_DEV_SECRET`, útil para pruebas de
humo antes de que existan usuarios sembrados. Para obtener el segundo:

```bash
npm run token:dev                    # estudiante por defecto
npm run token:dev -- uid-doc-1 DOCENTE
# usarlo como: Authorization: Bearer <token>
curl -H "Authorization: Bearer <token>" http://localhost:3000/api/v1/sesion
```

## Base de datos y semilla

```bash
npm run db:migrate   # aplica las migraciones SQL numeradas (idempotente)
npm run db:seed      # usuarios + claims, programa, periodo 2026-2, asignaturas, grupos,
                     # inscripciones, campus Calle 80 y horarios (idempotente)
```

Credenciales de demostración (todas con contraseña `Demo1234*`):

| Rol | Correo |
|---|---|
| Estudiante | `juan.rojas@demo.uniminuto.test` (también `maria.cardenas@`, `andres.molina@`) |
| Docente | `carolina.pena@demo.uniminuto.test` (también `diego.suarez@`) |
| Admin académico | `luisa.castro@demo.uniminuto.test` |
| Admin espacios | `camilo.vega@demo.uniminuto.test` |
| Seguridad | `jorge.salazar@demo.uniminuto.test` |
| Soporte | `natalia.gomez@demo.uniminuto.test` |
| Auditor | `oscar.rincon@demo.uniminuto.test` |

La semilla crea esos usuarios en Firebase Authentication y fija sus *custom claims* `roles`.

## Carnet y acceso (Fase 2)

| Endpoint | Quién | Qué hace |
|---|---|---|
| `GET /api/v1/carnet/mio` | autenticado | Carnet, dispositivo activo y último certificado |
| `POST /api/v1/dispositivos` | autenticado | Vincula el teléfono (JWK EC P-256) y emite certificado ES256 de 30 días |
| `DELETE /api/v1/dispositivos/{id}` | dueño o Soporte | Revoca el dispositivo y lo suma a la lista de revocación |
| `POST /api/v1/dispositivos/renovar-certificado` | autenticado | Emite un certificado nuevo para el dispositivo activo |
| `GET /api/v1/acceso/revocaciones` | Seguridad | Lista de revocación con versión (para validadores offline) |
| `POST /api/v1/auditoria/accesos` | Seguridad | Lote de hasta 100 validaciones (idempotente por id de evento) |

La clave privada institucional nunca sale del backend; la app del validador solo lleva la pública
(`app/assets/keys/institution_jwks.json`).

## Aulas virtuales, calificaciones y comunicación (Fase 3)

| Endpoint | Quién | Qué hace |
|---|---|---|
| `GET /api/v1/aulas` · `GET /api/v1/aulas/{id}` | miembros o admin | Aulas, unidades, contenidos y actividades (tarea, cuestionario, foro) |
| `GET /api/v1/mis-notas` | estudiante | Notas por corte y actividad con pesos y definitiva |
| `POST /api/v1/entregas` | estudiante | Entrega idempotente por UUID de cliente (ENVIADA/TARDIA con gracia de 24 h) |
| `GET /api/v1/actividades/{id}/entregas` | docente del grupo | Entregas con estudiante, texto, estado, inscripción y nota |
| `GET /api/v1/cuestionarios/{id}` · `POST /api/v1/cuestionarios/{id}/intentos` | estudiante | Preguntas sin respuesta correcta e intento único autocalificado |
| `GET /api/v1/cuestionarios/{id}/intentos` | docente del grupo | Revisión de intentos (puntaje y respuestas, D-69) |
| `POST /api/v1/archivos/subida` · `GET /api/v1/archivos/{id}/url` | autenticado | URL prefirmada PUT/GET del datalake (10/15 min, máximo 50 MB) |
| `PUT /api/v1/calificaciones` | docente del grupo | Califica en una transacción: upsert, nota del corte, auditoría y aviso (D-68) |
| `GET /api/v1/aulas/{id}/calificaciones` | docente del grupo | Matriz estudiante × actividad para calificar |
| `POST /api/v1/anuncios/{id}/replicar-correo` | docente del aula | Correo simulado por estudiante (idempotente por anuncio, D-48) |
| `GET /api/v1/correos-simulados` | autenticado | Bandeja simulada propia |

Foros y anuncios viven en **Cloud Firestore** (D-47, D-48): cada actividad tipo `FORO` tiene su
foro (`foros/{actividadId}/hilos`), los anuncios en `anuncios/{aulaId}/items` y la app los escucha
en tiempo real. La semilla escribe el espejo `aulas_index/{aulaId}` (`miembros` y `docentes`) con
el Admin SDK, que es lo que leen las reglas de seguridad.

Las reglas se despliegan con `npm run rules:deploy` (usa la cuenta de servicio y la API REST de
Firebase Rules, D-65); `firebase deploy --only firestore:rules --config infra/firebase/firebase.json`
sigue siendo válido.

## Horarios, módulo académico y evaluación docente (Fase 4)

| Endpoint | Quién | Qué hace |
|---|---|---|
| `GET /api/v1/mi-horario` | estudiante o docente | Bloques de la semana con asignatura, grupo, docente y ubicación del salón (edificio, piso, sede) |
| `GET /api/v1/mis-asignaturas` | estudiante o docente | Inscritas con créditos, docente, aula y si ya fue evaluada; para el docente, sus grupos |
| `GET /api/v1/espacios/edificios` · `…/edificios/{id}/pisos` · `…/pisos/{id}/salones` | autenticado | Jerarquía Edificio → Piso → Salón del campus Calle 80 (§4.3) |
| `POST /api/v1/evaluaciones-docentes` | estudiante | Evaluación única por inscripción: cinco criterios en escala 1–5 y comentario opcional (D-70) |
| `GET /api/v1/evaluaciones-docentes/resumen` | Admin Académico | Agregados por docente (promedios por criterio, D-49); no expone comentarios identificables |

La evaluación docente vive en la migración `0007` (tabla `evaluacion_docente`, única por
inscripción). En la app, **Mi horario**, **Mis asignaturas** (con evaluación docente y acceso del
docente a calificar) y **Campus** consumen estos endpoints; el horario y las notas se guardan en
Hive con vigencia de 12 h y se muestran sin conexión con un aviso (D-71).

## Pruebas

```bash
npm run api:test     # vitest: health, auth, carnet, aulas, calificaciones, correos, horarios,
                     # evaluación docente, espacios y transacciones
npm run app:test     # flutter test: PhoneFrame, caché Hive, localización y verificador
flutter analyze app  # sin errores (con Flutter 3.50 solo avisos de SDK, D-66)
```

## App Flutter

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define-from-file=env/dev.json   # Web con marco de teléfono
flutter run --dart-define-from-file=env/dev.json             # Android/emulador
```

`lib/core/config/firebase_options.dart` es un **archivo de ejemplo** hasta que la Fase 1 ejecute
`flutterfire configure`; mientras tanto el login permite "Entrar en modo muestra" para recorrer el
esqueleto. Las claves institucionales se generan con `node infra/scripts/generate-keys.mjs`.

## Reglas de Firestore

```bash
firebase deploy --only firestore:rules,firestore:indexes --config infra/firebase/firebase.json
```

## Estado por fases

| Fase | Estado |
|---|---|
| 0A — Cimientos (repo, infra, migraciones base, esqueleto API) | ✅ completada (2026-11-12) |
| 0C — Credenciales de nube, `.env` y verificación de `/health` + auth | ✅ completada (2026-11-12) |
| 0B — Claves ES256, esqueleto Flutter, reglas Firestore | ✅ completada (2026-11-12) |
| 1 — Autenticación, roles y semilla | ✅ completada (2026-11-13) |
| 2 — Carnet y QR offline | ✅ completada (2026-11-13) |
| 3 — Aulas virtuales y calificaciones | ✅ completada (2026-11-14) |
| 4 — Horarios y módulo académico | ✅ completada (2026-11-14) |
| 5 — Panel administrativo y auditoría | pendiente |
| 6 — Cierre y demo pública | pendiente |
