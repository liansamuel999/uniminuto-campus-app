# Guía de demo — Uniminuto Campus App

Guion para recorrer la aplicación de muestra y verificar los criterios de aceptación de cada fase
(§9 de [`arquitectura.md`](arquitectura.md)). **Todos los datos son ficticios**: no hay integración
real con Génesis, U-Wallet, torniquetes ni correo.

## 1. Puesta en marcha

```bash
# 1) Datalake local (MinIO). Crea el bucket privado campus-app.
npm run infra:minio

# 2) Base de datos: migraciones + datos de demostración (idempotente).
npm run db:migrate
npm run db:seed

# 3) API en http://localhost:3000
npm run api:dev
curl http://localhost:3000/health
# → {"estado":"ok","db":"ok","storage":"ok","version":"0.1.0"}
```

La API necesita `api/.env` con `DATABASE_URL` (CockroachDB Cloud con TLS) y la cuenta de servicio de
Firebase en `api/config/firebase-service-account.json` (ver [`../README.md`](../README.md)). Las
reglas de Firestore se publican con `npm run rules:deploy` (o `firebase deploy`). Los foros y
anuncios se leen a través de la API, que usa el Admin SDK (D-78).

App Flutter:

```bash
cd app
flutter pub get
flutter run -d chrome --web-port=5173 --dart-define-from-file=env/dev.json   # Web con marco de teléfono
flutter run --dart-define-from-file=env/dev.json                             # Android/emulador
```

> En Web usa siempre el mismo puerto (`--web-port=5173` o `npm run app:web`): la llave del
> dispositivo se guarda por origen y, si el puerto cambia, el carnet pedirá volver a vincular el
> navegador para mostrar el QR de ingreso.

## 2. Credenciales de demostración

Contraseña única para todas las cuentas: **`Demo1234*`** (dominio ficticio `@demo.uniminuto.test`).

| Rol | Correo | Para mostrar |
|---|---|---|
| Estudiante (Ing. Sistemas) | `juan.rojas@demo.uniminuto.test` | Carnet, aulas, entregas, notas, horario, reservas, incidencias |
| Estudiante (Administración) | `paula.mendoza@demo.uniminuto.test` | Cursos de su programa y sus notas |
| Estudiante (Psicología) | `isabella.gomez@demo.uniminuto.test` | Cursos de su programa y sus notas |
| Docente | `carolina.pena@demo.uniminuto.test` | Dos cursos de Bases de Datos con códigos distintos (1235 y 2235), calificar entregas, intentos, anuncios |
| Docente | `andrea.rincon@demo.uniminuto.test` | Curso de Inteligencia Artificial con material y entregas |
| Admin académico | `luisa.castro@demo.uniminuto.test` | Periodos, asignaturas, cursos, inscripciones, planificador y evaluación docente |
| Seguridad | `jorge.salazar@demo.uniminuto.test` | Modo validador del QR offline |
| Soporte | `natalia.gomez@demo.uniminuto.test` | Gestión de incidencias |
| Auditor | `oscar.rincon@demo.uniminuto.test` | Visor de auditoría (solo lectura) |

> En `ENTORNO=dev` el login precarga la cuenta y muestra el recordatorio de credenciales (D-62).

## 3. Guion de demo (10–12 minutos)

### 3.1 Fase 1 — Sesión y roles
1. Entra como estudiante: la navegación inferior muestra Inicio, Carnet, Aulas, Horario y Perfil.
2. Sal y entra como Seguridad: verá solo Inicio, Incidencias y Perfil (el validador de QR no se ofrece
   al personal administrativo); como Auditor aparece su panel.
3. En Perfil se ve el aviso “Proyecto de muestra – datos ficticios” y, solo para estudiantes, el
   programa y el código; el botón de editar datos no aparece (la foto sí se puede cambiar).

### 3.2 Fase 2 — Carnet y QR offline
1. Como estudiante, abre **Carnet**: se muestra el carnet, el QR dinámico (30 s), el código de
   barras y el dispositivo vinculado.
2. Activa el modo avión (o detén la API) y vuelve a abrir el carnet: sigue visible desde la caché.
3. Como Seguridad, abre **Validador** y escanea/carga el QR: acepta el QR vigente, rechaza uno
   vencido o repetido. La lista de revocaciones se descarga al entrar.

### 3.3 Fase 3 — Aulas, entregas, cuestionarios, foros y anuncios
1. Estudiante → **Aulas virtuales**: arriba están las **Próximas entregas** (con el tiempo restante) y
   cada curso muestra su docente. Toca una entrega próxima para ir directo a la actividad.
2. Dentro del curso: **Participantes** (con correo y opción de escribir) y **Calificaciones**; los
   contenidos (PDF, video, enlace, anuncio) se abren al tocarlos.
3. **Tarea**: escribe una respuesta o adjunta un archivo; *Guardar para enviar después* la encola y
   se envía sola al reconectar (sin duplicados). Si ya entregaste, la pantalla lo indica.
4. **Cuestionario**: primero una pantalla con título, descripción e «Iniciar intento»; si sales sin
   enviar puedes volver a entrar, pero al enviarlo se registra el único intento.
5. **Foro de discusión**: crea un hilo y responde. Docente → icono de anuncios: publica un anuncio
   importante y verifica «replicado a N estudiante(s)»; el estudiante lo ve en **Bandeja simulada**.
6. Docente → **Calificar el curso**: elige una actividad, revisa las entregas (texto y adjuntos) o
   los intentos del cuestionario y asigna nota y retroalimentación. También puede editar el aula,
   sus unidades, contenidos y actividades (incluida la fecha de cierre y los formatos aceptados).

### 3.4 Fase 4 — Horario, módulo académico y evaluación
1. Estudiante → **Horario**: bloques por día con salón, edificio y piso; toca un bloque para ver
   el detalle del salón. Sin red se muestra el horario guardado con el aviso “sin conexión”.
2. **Campus**: despliega Edificio → Piso → Salón.
3. **Mis asignaturas**: docente, créditos y botón **Evaluar docente** (única por asignatura).
4. **Mis notas** muestra únicamente la nota de cada corte y la definitiva del curso; mientras algún
   corte siga abierto aparece «en curso» y la definitiva oficial se publica al cerrar los cortes.
   El detalle por actividad está en **Calificaciones** del curso.
5. Admin académico → `GET /evaluaciones-docentes/resumen` (API) muestra los agregados por docente.

### 3.5 Fase 5 — Paneles administrativos, incidencias y auditoría
1. **Admin académico** → *Administración académica*: crea un periodo, una asignatura y un grupo;
   asigna docente a un grupo (queda evento `ASIGNAR_DOCENTE`); inscribe a un estudiante.
2. **Admin de espacios** → *Espacios y horarios*: crea un piso y un salón, y asigna el salón a una
   franja de horario del grupo. Intenta borrar un piso con salones: la API responde `409 CONFLICTO`.
3. **Soporte** → *Gestión de incidencias*: filtra por estado y cambia una incidencia a `RESUELTA`
   con resolución. Cualquier otro rol puede **reportar** una incidencia desde el inicio.
4. **Auditor** → *Auditoría*: filtra por acción/fechas y comprueba que solo puede leer (no hay
   acciones de edición o borrado).

## 4. Verificación automatizada

```bash
npm run api:test     # 125 pruebas de la API (vitest)
npm run app:test     # 15 pruebas de Flutter
cd app && flutter analyze   # 0 errores y 0 warnings de código
```

Además del smoke test manual, la Fase 3/4/5 se validó contra la base real con un script que recorre
RBAC, CRUD, incidencias y auditoría (ver commits de cada fase).

## 5. Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `/health` responde `503` con `storage` | MinIO no está levantado o el bucket no existe: `npm run infra:minio` y esperar el arranque. |
| La app no inicia sesión | Falta la cuenta de servicio de Firebase o la contraseña no es `Demo1234*`; revisa `api/config/firebase-service-account.json` y `api/.env`. |
| Foros/anuncios dan “permission-denied” | Reglas de Firestore sin desplegar: `npm run rules:deploy` (o `firebase deploy --only firestore:rules`). |
| El login muestra “operación no permitida” en Web | El dominio no está en los dominios autorizados de Firebase Authentication (solo en despliegue). |
| `EADDRINUSE: 3000` | Otra instancia de la API sigue corriendo: ciérrala o usa `PORT=3001`. |
| `flutter analyze` reporta avisos de `material.dart` | SDK Flutter 3.50 en la PC vs 3.41.9 del proyecto (D-66); no son errores de código. |
| El carnet no valida sin red | La caché del carnet solo se llena tras abrirlo una vez con conexión. |

## 6. Límites de la muestra

- Sin envío real de correo (los anuncios importantes se replican en `correo_simulado`).
- Sin notificaciones push: la API deja avisos en Firestore (`notificaciones/{uid}/items`) y la
  bandeja visual con badge queda como pulido posterior (D-42).
- Sin integración real con el sistema académico (Génesis), torniquetes ni biblioteca.
- Los usuarios y datos son ficticios; el QR y los certificados se emiten con claves de prueba.
