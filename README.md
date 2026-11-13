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
- Docker Desktop (CockroachDB y MinIO locales)
- Firebase CLI y FlutterFire CLI a partir de la Fase 1

## Arranque rápido (Fase 0)

```bash
# 1. Infraestructura local: CockroachDB en 26257 y MinIO en 9000/9001.
#    Crea la base `campus` y el bucket privado `campus-app` automáticamente.
npm run infra:up

# 2. Base de datos
npm run db:migrate

# 3. API (requiere api/.env; ver api/.env.example)
npm run api:dev

# 4. Verificación: {"estado":"ok","db":"ok","storage":"ok",...}
curl http://localhost:3000/health
```

> **Nota sobre MinIO (D-58).** MinIO retiró `minio/minio` y `minio/mc` de Docker Hub en septiembre de
> 2026. El `docker-compose.yml` usa la imagen de Bitnami —mismo servidor MinIO, misma API S3— fijada
> por tag inmutable, y crea el bucket con `MINIO_DEFAULT_BUCKETS`. El código no cambia: solo habla S3.

### Token de prueba (solo desarrollo)

Mientras no exista el proyecto Firebase (Fase 1), la API acepta tokens HS256 firmados con
`AUTH_DEV_SECRET` (decisión D-20). Para obtener uno:

```bash
npm run token:dev
# copiar el token y usarlo como: Authorization: Bearer <token>
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
| 0B — Claves ES256, esqueleto Flutter, reglas Firestore | pendiente |
| 1 — Autenticación, roles y semilla | pendiente |
| 2 — Carnet y QR offline | pendiente |
| 3 — Aulas virtuales y calificaciones | pendiente |
| 4 — Horarios y módulo académico | pendiente |
| 5 — Panel administrativo y auditoría | pendiente |
| 6 — Cierre y demo pública | pendiente |
