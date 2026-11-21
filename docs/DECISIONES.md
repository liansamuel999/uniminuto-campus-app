# DECISIONES — Uniminuto Campus App

Registro de las decisiones **no cubiertas explícitamente** por [`arquitectura.md`](arquitectura.md).
Según la regla de lectura del documento (línea 4), toda ambigüedad se resuelve con la opción más
simple coherente con el stack y se registra aquí. Ninguna decisión de este archivo cambia el stack,
el alcance ni los contratos fijados en el documento fuente.

## Cómo se usa este registro

- Cada decisión tiene un **ID estable** (`D-01`…). Los commits y revisiones de código citan el ID.
- **Estado**: `vigente` (aplicada), `revisada` (ajustada después de aprobada) o `sustituida`.
- Si una decisión se cambia, **no se borra**: se marca `sustituida` y se añade la nueva con su ID.
- Las decisiones se registraron al aprobar el plan de ejecución por fases (2026-11-12). Ninguna
  quedó congelada ni modificada por el cliente.

## Resumen por área

| Área | IDs | Fase de aplicación |
|---|---|---|
| A. Repositorio y proceso | D-01 – D-08 | 0 |
| B. Base de datos y migraciones | D-09 – D-15 | 0–4 |
| C. API | D-16 – D-24 | 0–3 |
| D. Seguridad y criptografía | D-25 – D-34 | 0, 2 |
| E. App Flutter | D-35 – D-43 | 0B–3 |
| F. Dominio | D-44 – D-54 | 1–5 |
| G. Archivos y Firestore | D-55 – D-57 | 3 |
| H. Infraestructura local | D-58 | 0 |
| I. Credenciales locales | D-59 | 0 |
| J. Claves institucionales | D-60 | 0B |
| K. Semilla y demo | D-61 – D-62 | 1 |
| L. Foros, comunicación y reglas (Fase 3) | D-65 – D-69 | 3 |
| M. Módulo académico y evaluación docente (Fase 4) | D-70 – D-71 | 4 |
| N. Administración, incidencias y auditoría (Fase 5) | D-72 – D-74 | 5 |
| O. Cierre y demo pública (Fase 6) | D-75 – D-77 | 6 |
| P. Correcciones de experiencia por rol | D-78 – D-89 | 3–6 |

---

## A. Repositorio y proceso

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-01 | La raíz del repositorio es la carpeta del proyecto; `app/`, `api/`, `infra/` y `docs/` cuelgan directamente de ella (estructura §7.1). | Anidar todo en un subdirectorio `campus_app/`. |
| D-02 | **npm** como único gestor de paquetes Node; sin *workspaces* (no hay paquetes JS compartidos entre `app/` y `api/`). El `package.json` raíz solo orquesta scripts. | pnpm (no está instalado y no aporta aquí). |
| D-03 | `engines.node >= 20`; desarrollo y CI con **Node 22 LTS** (`.nvmrc` = 22), alineado con el despliegue en Render. | Usar la versión 26 del equipo (rompe la reproducibilidad frente a Render). |
| D-04 | Prettier + ESLint en `api/`; `flutter_lints` + `dart format` en `app/`. Ancho de línea 100 en ambos. | Biome (menos estándar para revisores académicos). |
| D-05 | Pruebas: **Vitest** + `app.inject()` en la API; `flutter_test` + `mocktail` en la app. Cobertura ≥ 80 % solo en JWT, cálculo de notas, RBAC y reintento de transacciones. | Jest/supertest; pruebas end-to-end en todas las fases. |
| D-06 | CI mínimo en GitHub Actions (`flutter analyze` + `npm test`) se añade en la Fase 6, cuando el repo se publique. | CI desde el inicio (no hay repositorio remoto todavía). |
| D-07 | **Sin registro público de usuarios**: solo el script de semilla crea cuentas; no existe endpoint de *signup* (no está en §7.7). | Autoregistro con verificación de correo (añade alcance no pedido). |
| D-08 | Nombres de código (clases, variables, archivos) en inglés; tablas, entidades de dominio y textos de interfaz en español, como ya fija el documento. | Traducir también el modelo de datos al inglés. |

## B. Base de datos y migraciones

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-09 | Migraciones con **node-pg-migrate** y archivos `.sql` en `infra/migrations`, ejecutados por `api` con `migrations-dir` apuntando a `../infra/migrations` y tabla `pgmigrations`. Los archivos usan el prefijo numérico que exige la herramienta (**13 dígitos, epoch en milisegundos**); su nombre visible es `<timestamp>_<nombre>.sql`. | Prefijo humano `0001_…` (node-pg-migrate solo reconoce prefijos de 13 o 17 dígitos); runner propio. |
| D-10 | PK `UUID DEFAULT gen_random_uuid()`; `entrega.id` se genera en el cliente como UUIDv4 y **es** la clave de idempotencia de `POST /entregas`. | Seriales autoincrementales (peores para datos distribuidos y para idempotencia de cliente). |
| D-11 | Enumeraciones como `TEXT` + `CHECK` constrains, no tipos `ENUM` nativos (permite añadir valores sin migración destructiva). | `CREATE TYPE … AS ENUM`. |
| D-12 | Todas las fechas como `timestamptz`; `horario.dia_semana` es `SMALLINT` ISO-8601 (1 = lunes) y las horas son `time`; la presentación usa `America/Bogota`. | Guardar "lunes" como texto (rompe ordenamientos y filtros). |
| D-13 | Esquema único `public`, tablas en singular y español. Claves foráneas `ON DELETE RESTRICT`; baja lógica mediante `estado` donde el documento ya lo define (`usuario`, `carnet`, `dispositivo`, `incidencia`). | Borrado físico en cascada. |
| D-14 | `withTx()` es el **único** punto de transacción: reintenta hasta 3 veces solo ante SQLSTATE `40001`, con espera exponencial 50/100/200 ms y liberación de la conexión entre intentos. | Reintentos dispersos por módulo. |
| D-15 | Los índices se crean en la migración de su tabla (FKs y consultas del contrato §7.7). Sin particionado ni réplicas en la muestra. | Índices "después, si hace falta". |

## C. API

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-16 | Monolito modular: un plugin de Fastify por módulo; `src/app.ts` construye la app (testeable), `src/server.ts` escucha. La configuración de entorno se valida con Zod al arrancar y falla rápido. | Serverless/Cloud Functions (exige plan de pago, ver §3.2). |
| D-17 | Errores con forma estricta `{codigo, mensaje}`; `codigo` en `SCREAMING_SNAKE` español (`NO_AUTORIZADO`, `PROHIBIDO`, `DATOS_INVALIDOS`, `NO_ENCONTRADO`, `CONFLICTO`, `ERROR_INTERNO`, `SERVICIO_NO_DISPONIBLE`) y mapeo HTTP 400/401/403/404/409/422/500/503. | Envolver todas las respuestas en `{ok, data}` (el documento no lo pide). |
| D-18 | Paginación por cursor opaco (base64url de `{orden, id}`), `limite` por defecto 20 y máximo 100; respuesta `{items, siguiente_cursor}`. | Offset/limit (inestable con inserciones concurrentes). |
| D-19 | `GET /health` verifica base de datos y almacenamiento con timeout de 2 s; responde 200 si ambos están `ok` (o el almacenamiento `no_configurado`) y 503 si alguno falla. Sin autenticación. | `/health` que solo devuelve "ok" sin comprobar dependencias. |
| D-20 | Verificación de token **inyectable**: `TokenVerifier` con implementación Firebase (`verifyIdToken`) en producción y `DevTokenVerifier` (HS256 con `AUTH_DEV_SECRET`) **solo** cuando `ENTORNO=dev`. Permite cerrar la Fase 0 sin proyecto Firebase. | Bloquear la Fase 0 hasta crear Firebase; o dejar un bypass sin restricción de entorno. |
| D-21 | Los *custom claims* llevan `roles: string[]`. La API autoriza si el rol exigido está en los claims; **no existe "rol activo" en el servidor**. El selector de rol es solo de interfaz y no cambia permisos. | Enviar `X-Rol-Activo` y confiar en él (falsificable y redundante). |
| D-22 | CORS con lista explícita de `CORS_ORIGINS`, sin comodines; métodos y cabeceras declarados. Sin rate-limit ni helmet en la muestra (Render/Hosting ya dan TLS). | `origin: true` o `*`. |
| D-23 | `API_BASE_URL` incluye el prefijo completo (`https://host/api/v1`); el cliente añade rutas relativas. | Concatenar `/api/v1` en cada llamada. |
| D-24 | No se genera OpenAPI/Swagger: el contrato es §7.7 más este registro. | Documentación automática (alcance no pedido). |
| D-63 | En `ENTORNO=dev`, CORS acepta además cualquier puerto de `localhost`/`127.0.0.1` (Flutter Web elige un puerto aleatorio en cada `flutter run`) sin abrir el origen a dominios externos; en producción solo aplica la lista explícita de `CORS_ORIGINS`. | Fijar un puerto con `--web-port` (frágil y fácil de olvidar) o permitir `*` (prohibido por D-22). |
| D-64 | Un `Content-Type: application/json` con cuerpo vacío se interpreta como `{}` (no como error 400). Varios clientes HTTP envían esa cabecera en `POST`/`DELETE` sin datos; la API mantiene la validación normal para cuerpos no vacíos e inválidos. | Rechazar el cuerpo vacío (obliga al cliente a recordar quitar la cabecera) o aceptar cualquier cuerpo (peligroso). |

## D. Seguridad y criptografía

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-25 | `infra/scripts/generate-keys.mjs` (jose) genera un par **ES256** y un `kid`; la privada va a `.env` (gitignored) y la pública a `app/assets/keys/institution_jwks.json`, **versionada**, como lista `kid → JWK` para permitir rotación. | Clave única sin `kid` (impide rotar sin recompilar). |
| D-26 | El QR codifica la concatenación `<certificado>.<tokenQR>`. Como base64url no contiene `.`, la cadena resultante tiene 6 segmentos y se parte en 3 + 3. | Separador alternativo (`~`, `|`) y parseo por búsqueda de prefijo. |
| D-27 | Nivel de corrección de errores del QR: **L** cuando el payload supere ~1,2 KB; se mide en Fase 2 y nunca se recortan claims más allá de lo que fija §6.1. | Nivel H/M fijo (reduce la capacidad útil del QR). |
| D-28 | `jti` = contador creciente + 6–8 caracteres aleatorios; la caché anti-repetición del validador guarda 5 minutos y se purga por antigüedad. | UUID completo (alarga el QR sin aportar seguridad). |
| D-29 | En Web la clave del dispositivo es un `CryptoKey` P-256 **no exportable** de WebCrypto, persistido en IndexedDB. Si el navegador no puede persistirlo, la app pide revincular en ese equipo y lo explica en la ayuda. | Exportar la clave a `localStorage` (anula el requisito "no exportable"). |
| D-30 | En móvil la clave privada del dispositivo se guarda con `flutter_secure_storage` (Keystore). Se documenta la limitación real: **no es hardware-backed**, pues `dart_jsonwebtoken` necesita la clave en el proceso Dart. | Implementar firma nativa con clave no exportable del Keystore (fuera de alcance de la muestra). |
| D-31 | Certificado de carnet con `exp` de 30 días; la app pide renovación en segundo plano si faltan < 7 días y hay red. Sin red y con certificado vencido, el QR muestra "Conéctate para renovar el carnet". | Renovación solo manual. |
| D-32 | `GET /acceso/revocaciones` devuelve `{version, actualizado_en, carnets[]}`; el validador la refresca al recuperar red y la muestra con fecha de última sincronización. | Lista embebida en el build (nunca se actualizaría). |
| D-33 | Los eventos del validador se envían en lotes de máximo 100; el `id` del evento se genera en el dispositivo y se inserta con `ON CONFLICT DO NOTHING` para deduplicar. No se añaden campos a `evento_auditoria`. | Reintentar sin idempotencia (duplicaría auditoría). |
| D-34 | El cambio de contraseña exige reautenticación previa (flujo real de Firebase) y valida un mínimo de 8 caracteres en el cliente antes de llamar. | Cambio directo sin reautenticar. |

## E. App Flutter

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-35 | Riverpod con providers manuales y modelos con `fromJson`/`toJson` escritos a mano; sin `freezed` ni `build_runner` en la muestra. | Codegen con freezed/json_serializable (más toolchain para pocos modelos). |
| D-36 | Textos de interfaz en español dentro de constantes por *feature*; `intl` solo para formato de fechas y números. Sin ARB ni múltiples locales. | Internacionalización completa (una sola locale en alcance). |
| D-37 | Material 3, tema claro con azul institucional neutro (`#1B3A6B`), sin logotipos oficiales ni assets con licencia. | Tema oscuro y branding oficial. |
| D-38 | `go_router` con `ShellRoute` y navegación inferior por rol; las guardas redirigen a `/login` o a la home del rol. El selector de rol solo aparece si el usuario tiene más de uno. | Rutas imperativas con `Navigator`. |
| D-39 | `PhoneFrame` en el widget raíz: en Web y pantallas > 600 px limita a 430 px de ancho con alto de viewport, borde sutil y fondo neutro; en pantallas angostas ocupa todo el ancho. | Marco por pantalla (duplicaría lógica). |
| D-40 | Hive (`hive_ce`) con una caja por dominio (`carnet`, `horario`, `notas`, `validador_jti`, `validador_eventos`, `config`), cada una con versión de esquema y TTL explícito. | Una única caja con claves prefijadas (difícil de versionar y limpiar). |
| D-41 | En Web se habilita la persistencia de Firestore; si el SDK devuelve `failed-precondition` por otra pestaña abierta, la app continúa en memoria y muestra un aviso. | Deshabilitar persistencia en Web (perdería escritura offline). |
| D-42 | Las notificaciones son una bandeja interna con badge; **no** se usa push ni Firebase Cloud Messaging. | Notificaciones push (fuera de alcance y sin backend de pago). |
| D-43 | El aviso "Proyecto de muestra – datos ficticios" es un widget único, visible en login y perfil. | Aviso repetido por pantalla. |

## F. Dominio

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-44 | Notas redondeadas a 2 decimales (mitad hacia arriba) solo en el último paso; las actividades sin calificar no entran al denominador; si la suma de pesos calificados es 0 la nota de corte es nula; un corte sin nota cuenta como 0 en la definitiva. | Redondear en cada paso (arrastra error en la definitiva). |
| D-45 | `peso_porcentual` es `DECIMAL(5,2)` por actividad y por corte; `nota_máxima` por defecto 5.00 y nunca menor que la nota registrada. La API rechaza publicar una actividad que haga exceder 100 % en su corte. | Validar solo en la interfaz. |
| D-46 | **Cuestionarios: un único intento** por estudiante (el primero registrado); la autocalificación y el recálculo de `nota_corte` ocurren en la misma transacción. | Múltiples intentos con mejor nota (el documento no lo define; añadiría alcance). |
| D-47 | `foroId` de Firestore = `actividad_id`; los adjuntos usan el prefijo `foros/{foroId}/…`. | Colección de foros paralela con su propio id (duplicaría identidad). |
| D-48 | Los anuncios de aula viven en Firestore (`anuncios/{aulaId}/items`); `contenido` tipo `ANUNCIO` cubre solo anuncios dentro de una unidad. `POST /anuncios/{id}/replicar-correo` lo invoca el docente dueño del aula y es idempotente por anuncio y estudiante. | Anuncios solo en CockroachDB (perderían la sincronización en tiempo real). |
| D-49 | Se añade `GET /evaluaciones-docentes/resumen` (agregados, solo Admin Académico): §5 exige "R (agregados)" y §7.7 no lista el endpoint. No expone comentarios identificables. | No implementar los agregados (dejaría §5 sin cubrir). |
| D-50 | Incidencias: `POST /incidencias` y `GET /incidencias` (propias) para cualquier rol autenticado; `GET /incidencias?estado=` y `PUT /incidencias/{id}` solo Soporte. | Gestión por Administrador (la matriz §5 asigna Soporte). |
| D-51 | `GET /mis-notas` filtra por periodo activo y por las inscripciones del usuario; ordena por asignatura → corte → actividad. | Devolver todo el histórico y filtrar en el cliente. |
| D-52 | El horario no detecta choques de franjas; el detalle enlaza al salón del campus. | Validación de solapamientos (no pedida). |
| D-53 | Foto del carnet en `perfiles/{usuarioId}.jpg`, servida por URL prefirmada de lectura y cacheada en disco para uso offline. | URL pública del bucket (prohibido por §6.3). |
| D-54 | Semilla idempotente por clave natural (correo, código de asignatura/periodo/grupo, código de salón), contraseña demo `Demo1234*` y usuarios espejo en Firebase Auth con *custom claims*. Sin `FIREBASE_SERVICE_ACCOUNT`, el script corre solo contra la base de datos y lo advierte. | Semilla destructiva que recrea datos en cada ejecución. |

## G. Archivos y Firestore

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-55 | Validación de archivos por extensión + MIME declarado, límite de 50 MB aplicado en la URL prefirmada con `content-length-range`, y `HeadObject` antes de registrar el recurso en la base. | Confiar solo en lo que declara el cliente. |
| D-56 | URLs prefirmadas: subida 10 minutos, lectura 15 minutos. Respuestas `{objeto_key, url_put}` y `{url, expira_en}`. | URLs públicas o proxear el archivo por la API. |
| D-57 | Reglas e índices de Firestore viven en `infra/firebase/` y se despliegan a mano con `firebase deploy --only firestore:rules,firestore:indexes`. | Desplegar desde CI (no hay CI hasta la Fase 6). |

---

## H. Infraestructura local

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-58 | MinIO sigue siendo el datalake de desarrollo (§3.1), pero **la imagen ya no se publica en Docker Hub**: `minio/minio` y `minio/mc` se retiraron el 11/09/2026 y quay.io dejó de permitir descargas anónimas. Se usa la imagen empaquetada por Bitnami (`bitnamilegacy/minio:2025.7.23-debian-12-r5`, mismo servidor MinIO 2025.7.23 y misma API S3) fijada por tag inmutable, y el bucket privado `campus-app` se crea con `MINIO_DEFAULT_BUCKETS`, sin depender de `mc`. La API y la app no cambian: solo hablan S3 con `S3_ENDPOINT`/claves (§6.3), igual que con Cloudflare R2 en la demo. | Sustituir MinIO por otro servidor S3 (SeaweedFS, RustFS, Versity) — cambiaría el software fijado en §3.1; ejecutar el binario de MinIO fuera de Docker — rompería el arranque de §7.3 (`docker compose up`). |

---

## I. Credenciales locales

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-59 | La cuenta de servicio de Firebase se carga por **ruta de archivo**: `FIREBASE_SERVICE_ACCOUNT_PATH` (relativa a `api/`, o absoluta), con `FIREBASE_SERVICE_ACCOUNT` como alternativa para hosts sin sistema de archivos (Render). El archivo vive en `api/config/firebase-service-account.json` y la carpeta completa está en `.gitignore`. En `ENTORNO=dev`, si coexisten credenciales de Firebase y `AUTH_DEV_SECRET`, un `VerificadorCompuesto` acepta ambos tokens (Firebase primero, token de desarrollo como respaldo) para poder hacer pruebas de humo antes de sembrar usuarios; en producción solo se acepta Firebase y `AUTH_DEV_SECRET` está prohibido por validación de entorno. | Pegar el JSON en `FIREBASE_SERVICE_ACCOUNT` también en local (incómodo y propenso a filtrarlo en el historial del shell); permitir el token de desarrollo en producción (inaceptable). |

---

## J. Claves institucionales

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-60 | El par ES256 institucional se genera con `infra/scripts/generate-keys.mjs` (WebCrypto nativo, sin dependencias). La privada queda en `infra/keys/institution_private.jwk.json` (ignorada por git) y se carga con `INSTITUTION_PRIVATE_KEY_PATH` (relativa a `api/`) o con `INSTITUTION_PRIVATE_KEY` (JWK en una línea, para Render). La pública se publica como **JWKS** versionado en `app/assets/keys/institution_jwks.json` (array de claves con `kid`, `alg: ES256`, `use: sig`), para que el validador pueda rotar claves sin recompilar a ciegas. El `kid` sigue el formato `inst-<año-mes>-<6 hex>` para no engordar el QR. | Clave única sin `kid`; guardar la privada en el repositorio; embeber la privada en la app (prohibido por §6.1). |

---

## K. Semilla y demo

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-61 | El script de semilla vive en **`api/scripts/seed/`** (no en `infra/scripts/`) porque necesita las mismas dependencias de la API (`pg`, `firebase-admin`, `zod`, configuración de entorno) y las reglas de idempotencia del dominio. Se ejecuta con `npm run db:seed` desde la raíz, es idempotente por clave natural (correo, código, salón) y, si no hay cuenta de servicio, siembra la base con uids locales `demo-local-<código>` y avisa. | Duplicar `package.json`/`node_modules` en `infra/` solo para el script, o mover dependencias de la API a la raíz. |
| D-62 | El login precarga las credenciales de demostración y muestra un recordatorio de las cuentas de prueba **solo cuando `ENTORNO=dev`** (`AppConfig.esProduccion == false`). En producción el formulario arranca vacío. | Credenciales visibles siempre (riesgo de confusión en la demo pública). |

---

## L. Foros, comunicación y reglas (Fase 3)

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-65 | Las reglas de Firestore se despliegan también con **`npm run rules:deploy`** (`api/scripts/deploy-firestore-rules.mjs`): usa la cuenta de servicio de Firebase y la API REST de Firebase Rules, de modo que se pueden publicar desde una PC sin `firebase-tools` ni `firebase login` interactivo. `firebase deploy --only firestore:rules` sigue siendo válido y ambos caminos publican el mismo archivo `infra/firebase/firestore.rules`. | Instalar `firebase-tools` y exigir un login interactivo en cada equipo (la PC de la demo no lo tenía). |
| D-66 | La PC de la demo quedó con **Flutter 3.50.0 / Dart 3.14.0** frente a la versión fijada del proyecto (3.41.9 / Dart 3.11.5). No se migra a `package:material_ui` ni se baja el SDK: el código es el mismo y `flutter analyze` solo muestra los avisos `deprecated_member_use` del SDK al importar `package:flutter/material.dart`. Con Flutter 3.41.9 el análisis queda sin avisos. | Migrar los 33 archivos a `material_ui` (rompe la versión fijada y el APK) o degradar el SDK de toda la máquina. |
| D-67 | Los hilos y mensajes de foro guardan **`aula_id`** además del `foro_id` (= `actividad_id`, D-47). Las reglas validan la membresía de lectura/escritura contra `aulas_index/{aula_id}.miembros` con ese campo; al crear un mensaje comprueban además que `aula_id` coincide con el hilo padre. La semilla escribe el espejo `aulas_index` con el Admin SDK. | Guardar solo `foro_id` y resolver el aula con un `get()` adicional del documento padre en cada lectura. |
| D-68 | `PUT /calificaciones` deja una notificación en `notificaciones/{uid}/items` (Firestore) **después** de confirmar la transacción SQL. Es *best-effort*: si Firebase no está disponible, la calificación ya registrada no falla y solo se pierde el aviso. | Escribir la notificación dentro de la transacción (Firestore no participa en ella) o dejar al estudiante sin aviso de nota. |
| D-69 | Se añade **`GET /cuestionarios/{id}/intentos`** (docente dueño del grupo) porque §6.4 pide revisar los intentos y §7.7 no listaba el endpoint, con el mismo criterio que D-49. Devuelve estudiante, puntaje, fecha y respuestas del intento único. | No exponer los intentos y limitar al docente al puntaje agregado de la nota. |

---

## M. Módulo académico y evaluación docente (Fase 4)

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-70 | La evaluación docente usa **cinco criterios** fijos: `dominio`, `claridad`, `metodologia`, `evaluacion` y `acompanamiento`, cada uno entero de 1 a 5; la API exige los cinco y un comentario opcional de hasta 1000 caracteres. Es **única por inscripción** (`UNIQUE (inscripcion_id)`, §4.2) y el docente se toma del grupo de la inscripción, no del cuerpo de la petición. `GET /evaluaciones-docentes/resumen` solo lo ve el Admin Académico y devuelve promedios por criterio sin comentarios identificables (D-49). | Permitir criterios libres o evaluar por profesor sin asignatura; exponer comentarios en los agregados. |
| D-71 | La **caché offline de lectura** de la Fase 4 usa las cajas Hive `horario` y `notas` (D-40) con vigencia de **12 h**: al guardar una respuesta se escribe el JSON con marca de tiempo; si la petición falla por red se muestra el dato guardado con el aviso «sin conexión» y, si no hay caché vigente, se muestra el error. La escritura (entregas, evaluación docente) no se hace offline. | Guardar indefinidamente (datos viejos) o no cachear (incumple el criterio «el horario se ve sin conexión»). |

---

## N. Administración, incidencias y auditoría (Fase 5)

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-72 | La tabla `incidencia` (migración `0008`) guarda `usuario_id` (quien reporta), `descripcion`, `estado` (`ABIERTA`, `EN_PROCESO`, `RESUELTA`, `CERRADA`), `resolucion`, `atendida_por`, `creada_en` y `actualizada_en`. Cualquier rol autenticado crea y consulta las propias; Soporte consulta todas (opcionalmente por estado) y actualiza estado/resolución. La semilla crea dos incidencias ficticias para poder demostrar la bandeja de Soporte. | Tabla de tickets genérica con categorías y adjuntos (alcance no pedido) o no persistir las incidencias. |
| D-73 | Los endpoints administrativos se publican con rutas de recurso y RBAC de la matriz §5: `/periodos`, `/asignaturas`, `/grupos` (con `PUT /grupos/{id}` para asignar docente), `/inscripciones`, `/admin/usuarios?rol=`, CRUD de `/espacios/edificios|pisos|salones` y `/horarios`, `/incidencias` y `/auditoria`. **Se añaden al contrato §7.7** `GET /admin/usuarios` (selector de docentes/estudiantes), `GET /auditoria/acciones` (valores del filtro) y `GET /espacios/salones` (lista plana con ubicación), con el mismo criterio que D-49 y D-69. Los errores de integridad referencial (`23503`) y de duplicado (`23505`) se traducen a `409 CONFLICTO` con un mensaje de dominio. | Exponer un único endpoint `/admin` con acciones por `body` (peor contrato y peor RBAC por ruta) o dejar los selectores sin endpoint (el panel no podría asignar docentes). |
| D-74 | La auditoría es **estrictamente de solo lectura**: `GET /auditoria` (rol Auditor, filtros `desde`, `hasta`, `accion`, `actorId`, `antesDe` como cursor y `limite` 1–200) y `GET /auditoria/acciones`; no existen rutas de actualización ni borrado sobre `evento_auditoria`. La asignación de docente desde `PUT /grupos/{id}` escribe el evento `ASIGNAR_DOCENTE` (`grupo:{id}`, resultado `OK`) en la misma transacción del cambio, según §8.1. | Permitir que el Auditor modifique o borre eventos (rompe el propósito del rol) o no registrar el cambio de docente (incumple §8.1). |

---

## O. Cierre y demo pública (Fase 6)

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-75 | El despliegue queda **preparado en el repositorio** para ejecutarse cuando haya credenciales: `render.yaml` (blueprint de la API con `rootDir: api`, build `npm ci && npm run build`, `node dist/server.js`, health `/health` y secretos con `sync: false`), `firebase.json` + `.firebaserc` para Firebase Hosting (`app/build/web`, rewrite a `index.html`, cabeceras de caché) e `infra/r2/cors.json` para Cloudflare R2. La publicación se documenta con la CLI por `npx firebase-tools` (no requiere instalación global). Los íconos de la PWA y del launcher Android se generan con un script local (letra «U», colores institucionales neutros, sin logotipos oficiales) y se versionan en `app/web/icons/`, `app/web/favicon.png` y `app/android/app/src/main/res/mipmap-*/`. | Publicar con un servicio distinto a Render/Hosting (fuera del stack de §7.4) o dejar el despliegue sin archivos de apoyo (dependería de memoria del operador). |
| D-76 | La **guía de demo** (`docs/guia-demo.md`) es el documento de pruebas manuales del cierre: credenciales, recorrido de 10–12 minutos por fase, problemas frecuentes y límites de la muestra. La **guía de despliegue** (`docs/despliegue.md`) concentra variables de entorno, pasos por servicio y el checklist post-despliegue. El estado de la Fase 6 se marca «local completo; despliegue pendiente de credenciales» hasta que exista URL pública (criterio de aceptación de §9). | Un README monolítico con todo el guion (se degrada al crecer) o marcar la Fase 6 como cerrada sin URL pública. |
| D-77 | El APK se compila con el **SDK fijado del proyecto (Flutter 3.41.9)** y **JDK 21** configurado con `flutter config --jdk-dir` y `JAVA_HOME` (Temurin 21 en la PC de la demo). El Flutter 3.50 del sistema exige Gradle 9.5/AGP 9 y el wrapper del proyecto es 8.14, por lo que no se usa para el APK. Para que los plugins de Firebase (compilados con metadata Kotlin 2.4) enlacen, se fija **`kotlin_version = 2.4.20`** en `android/build.gradle.kts` (Flutter la lee para compilar los plugins) y el plugin usa el id completo `org.jetbrains.kotlin.android` con `jvmTarget` por `compilerOptions`; el alias `kotlin-android` resolvía el Kotlin embebido 2.2. Flutter 3.41.9 exige por defecto el **NDK 28.2.13676358**, que se instala con `sdkmanager` (la copia corrupta de una descarga interrumpida se eliminó y reinstaló). | Subir Gradle/AGP (riesgo de romper el template), dejar el Kotlin embebido (falla el enlace con Firebase) o dejar el NDK incompleto (CXX1101). |

---

## P. Correcciones de experiencia por rol (Fases 3–6)

| ID | Decisión registrada | Alternativa descartada |
|---|---|---|
| D-78 | **Foros y anuncios se sirven por la API** y no con el SDK de Firestore en el cliente. La API valida la pertenencia al aula/grupo en SQL y lee/escribe Firestore con el Admin SDK; el espejo `foros_index/{foroId}` se mantiene desde la semilla y al crear/eliminar una actividad tipo FORO. Motivo: Firestore no autoriza consultas de lista cuando la regla de membresía depende de `get()` (el motor rechaza la query con `permission-denied` aunque el documento individual sí se lea); pasar por la API evita ese límite y mantiene Firestore como almacén de foros/anuncios. Las pantallas refrescan al abrir, al deslizar y después de escribir. | Reintentar reglas con *custom claims* de aulas/foros (frágil al crear foros nuevos) o mover los foros a SQL (rompería la decisión D-47 de usar Firestore). |
| D-79 | `package:uuid` genera el identificador de entrega en el cliente. El generador casero anterior aplicaba un XOR sin máscara y producía cadenas de longitud inválida, por lo que la API respondía «Invalid UUID». Además, la actividad admite una lista de **formatos de archivo permitidos** (`actividad.formatos_permitidos TEXT[]`, migración `0009`); si está vacía, la app acepta cualquier formato de la muestra. | Mantener el generador propio (bug demostrado) o no restringir adjuntos (el docente no podría exigir PDF/PNG). |
| D-80 | **Notas: la definitiva solo se publica cuando cierran todos los cortes.** La API devuelve `corte.cerrado` (todas las actividades del corte con `cierra_en` vencido) y `definitivaPublicada` (todos los cortes cerrados); la pantalla del estudiante muestra «en curso» y oculta la definitiva provisional. «Mis notas» deja de listar actividades (solo corte y definitiva); el detalle por actividad se ve en **Calificaciones** del curso. | Recalcular y mostrar la definitiva en tiempo real (confunde al estudiante, como reportó el cliente) o congelar cortes por fecha del calendario sin mirar las actividades. |
| D-81 | La interfaz se adapta por rol en inicio y barra inferior: el estudiante mantiene Carnet/Aulas/Horario/Perfil; el **docente** tiene Mi QR en la barra y un inicio con Aulas, Horario, sus asignaturas y «Resumen de notas»; los **administrativos** ven solo su panel (académico, espacios, incidencias o auditoría) y **no tienen validador de QR**. El personal no estudiante ya no muestra programa académico, y el perfil del estudiante no se edita (solo la foto; los cambios de datos se gestionan en la oficina de registro). El inicio usa tarjetas compactas sin descripciones ni «fase» y sin el bloque Campus. | Mantener una única interfaz copiada para todos (el cliente lo reportó como confuso) o permitir que cualquier administrativo edite notas/datos académicos. |
| D-82 | El login **no muestra cuentas de demostración** ni pregarga credenciales, y los errores de acceso son siempre genéricos («Correo o contraseña incorrectos»): no se valida la longitud de la contraseña antes de enviar ni se distingue entre correo inexistente y contraseña incorrecta. Las credenciales de prueba siguen documentadas en `docs/guia-demo.md` para el evaluador. | Formulario con pistas de validación por campo (filtraba información) o cuentas demo visibles en producción. |
| D-83 | El datalake local se usa con **CORS abierto** (`MINIO_API_CORS_ALLOW_ORIGIN=*`) para que la app Web pueda subir con URL prefirmada desde cualquier puerto de desarrollo; se añade `GET /archivos/por-clave/url` para firmar la lectura de contenidos, adjuntos y foto de perfil por `objetoKey`. La semilla sube un PDF real de demostración a `aulas/demo/guia-unidad.pdf` y deja el video como enlace externo, de modo que los contenidos de la muestra sí se pueden abrir. | Proxy de todos los binarios por la API (rompe la decisión D-56 de URLs prefirmadas) o dejar contenidos que no abren nada. |
| D-84 | Se fija `path_provider_android: 2.2.17` con `dependency_overrides` en la app. La versión 2.3.x implementa las rutas con `package:jni` y compila C++ con CMake; con NDK 28.2 y CMake 3.22.1 en esta PC el *test compiler* de CMake falla y el APK no compila. La 2.2.x usa el canal nativo clásico y cubre lo que la muestra necesita (directorios de Hive y caché). | Subir CMake/AGP solo para compilar un plugin transitivo (mayor riesgo para el resto del APK) o dejar el APK sin compilar. |
| D-85 | **El rol Admin de Espacios se elimina de la muestra**: los salones y horarios los administra el **Admin Académico**, con un planificador automático (`api/src/modules/admin/planificador.ts`) que asigna salón según capacidad, necesidad de laboratorio y choques de horario, y permite volver a planificar o mover un horario a mano. Quitar un curso borra sus horarios e inscripciones, por lo que el horario del estudiante deja de mostrarlo. Los edificios/pisos/salones quedan bajo el admin académico. | Mantener un rol que solo “crea espacios” (el cliente lo consideró sin sentido) o asignar salones a mano (errores de choque/equipos). |
| D-86 | **Reentrega mientras la actividad esté abierta**: `POST /entregas` actualiza la entrega existente (texto y adjuntos) si `now() <= cierra_en`; al hacerlo invalida la calificación previa y recalcula la nota del corte para que el docente vuelva a revisarla. Además, cada actividad puede tener **archivos propios** (`actividad_recurso`, migración `0012`) que el docente sube desde el editor de la actividad y que el estudiante ve en la tarea o en la antesala del cuestionario; son independientes de los contenidos de la unidad. | Bloquear la entrega tras el primer envío (el cliente lo reportó como error) o adjuntar los archivos como contenidos de la unidad (no aparecen dentro de la actividad). |
| D-87 | **La subida de archivos usa un cliente HTTP sin el token de la API** (`ApiClient.putBinario`). El interceptor añadía `Authorization` también a la URL prefirmada de MinIO/S3 y el datalake la rechazaba por tener dos mecanismos de autenticación; era la causa de «no se pudo adjuntar» / «no se pudo guardar el contenido». El error de subida ahora se muestra con su detalle en lugar de un mensaje genérico. | Enviar el token a S3 (falla) o subir los binarios a través de la API (rompe la decisión D-56 de URLs prefirmadas). |
| D-88 | En el editor de actividades la **fecha y la hora de cierre se escriben a mano** (`AAAA-MM-DD` y `HH:MM` en formato 24 h), sin reloj modal: el selector anterior solo aceptaba horas menores de 12 y desbordaba en pantallas pequeñas. En Administración Académica las listas reservan espacio inferior para que el botón flotante «crear» no tape el menú de tres puntos (editar/eliminar) de los últimos elementos. El docente ya **no puede editar el nombre/descripción del curso**: esa edición queda en la oficina académica (API solo para `ADMIN_ACADEMICO`). | Mantener los selectores modales (mal en móvil y con validación de 12 h) o dejar que el docente renombre el curso (rompe la separación de roles). |
| D-89 | **El curso es la oferta académica y se identifica por su código único de curso** (tipo NRC), no por “grupo 01/02”. `grupo.codigo_curso` es obligatorio, único e ingresado por el admin académico (migraciones `0013` y `0014`); si un docente dicta dos cursos de la misma materia, aparecen como dos cursos con códigos distintos (p. ej. `1235` y `2235`). `numero_grupo` queda como detalle interno de la base y no se muestra. Aplica a Aulas, Mis asignaturas, Horario, Resumen de notas, planificador de salones y Administración Académica (pestaña **Cursos**). | Mantener la agrupación por número de grupo (el cliente la rechazó) o agrupar todo por código de asignatura (ocultaría que son ofertas distintas con docentes/horarios/estudiantes distintos). |
| D-90 | **Semilla de demostración ampliada** y autolimpiante: 3 programas, 26 usuarios (15 estudiantes repartidos en los programas, 6 docentes y 5 cuentas administrativas), 15 cursos con códigos NRC únicos, 3 unidades por aula, 7 actividades por curso (tareas, cuestionarios y foros), entregas con adjuntos, notas, intentos, anuncios, hilos de foro e incidencias. En cada pasada se eliminan cursos/actividades creados en pruebas con nombres sin sentido (`1111111`, `222211`, `lick`, `sss`, `hfyjv`, `yjyyg`, “Foro de discusión” genérico) y las asignaciones del rol `ADMIN_ESPACIOS` absorbido (D-85). | Mantener los datos de prueba mezclados con la demo o una semilla que solo agregue registros y nunca limpie los anteriores. |
| D-91 | **Generación automática de horario por curso**: el endpoint `POST /admin/grupos/{id}/generar-horario` usa los créditos como horas semanales, reparte en una o dos sesiones de máximo 2 h, respeta los turnos del docente (`usuario.turnos_disponibles`: mañana, tarde y noche) y evita choques de salón, docente y estudiantes. La creación/movimiento manual de horarios valida esos mismos choques. La semilla asigna turnos distintos a los docentes y ya no deja cruces de horario. | Mantener el planificador anterior, que solo reasignaba salón a franjas ya existentes y no validaba choques de docente/estudiante. |
| D-92 | **Mensajería interna** entre estudiantes y docentes que comparten al menos un curso: tabla `mensaje`, endpoints `/mensajes`, `/mensajes/contactos` y `/mensajes/{id}/leido`. La bandeja conserva los anuncios del aula y agrega los mensajes recibidos/enviados; el destinatario se valida contra los contactos reales del curso. | Correo real o chat en Firestore (más alcance y sin necesidad para la muestra). |
| D-93 | **Proceso de actualización y capa curada del data lake**: `POST /admin/analitica/actualizar` extrae agregados de CockroachDB, escribe un JSONL en el bucket (`analitica/etl/…`) y publica métricas en `analitica_metrica`; `GET /admin/analitica` alimenta la pestaña de indicadores y `GET /admin/analitica/export` entrega un enlace de descarga firmado. Es una implementación batch pequeña, no un motor de big data; no se afirma un data lake completo con catálogo y streaming. | Guardar archivos sin proceso ni consumo (data lake incompleto) o añadir Spark/Hadoop fuera del alcance de la muestra. |
| D-94 | **Endurecimiento del acceso**: contraseña de mínimo 8 caracteres con letras, números y símbolos, prohibición de repetir la actual y bloqueo total de edición de nombres/apellidos desde la aplicación (los cambios de identidad se tramitan en registro). No se añade captcha: una verificación que solo molesta al usuario y no protege realmente el flujo de Firebase Auth es peor que no tenerla. | Captcha cosmético o permitir que cualquier rol cambie su identidad desde el perfil. |
| D-95 | **Administración por programa/semestre y curso listo para usar**: `asignatura.programa_id` y `asignatura.semestre` filtran la oferta; en Inscripciones primero se elige carrera y semestre, luego la materia/curso, y la API rechaza matrículas de otro programa. Al crear un curso se crean su aula virtual, tres cortes y tres unidades, de modo que aparece de inmediato en Aulas y no solo en Horarios. | Filtrar solo en la interfaz o dejar el aula sin crear hasta una pasada de semilla. |

---

## Decisiones que NO se registran (ya cerradas en el documento)

Stack (§3), entidades y relaciones (§4.2), estructura del campus (§4.3), reglas de seguridad de
Firestore (§4.4), matriz RBAC (§5), flujos de QR, sincronización, archivos y notas (§6), estructura
del monorepo (§7.1), variables de entorno (§7.2), despliegue (§7.4–7.5), contrato de API (§7.7),
seguridad (§8) y orden de fases (§9).
