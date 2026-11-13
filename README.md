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

## Pruebas

```bash
npm run api:test     # vitest: health, auth y reintento de transacciones
```

## Estado por fases

| Fase | Estado |
|---|---|
| 0A — Cimientos (repo, infra, migraciones base, esqueleto API) | ✅ completada (2026-11-12) |
| 0C — Credenciales de nube, `.env` y verificación de `/health` + auth | ✅ completada (2026-11-12) |
| 0B — Claves ES256, esqueleto Flutter, reglas Firestore | pendiente |
| 1 — Autenticación, roles y semilla | pendiente |
| 2 — Carnet y QR offline | pendiente |
| 3 — Aulas virtuales y calificaciones | pendiente |
| 4 — Horarios y módulo académico | pendiente |
| 5 — Panel administrativo y auditoría | pendiente |
| 6 — Cierre y demo pública | pendiente |
