-- 1794441600000 · Base de identidad, roles y auditoría
-- Referencias: arquitectura.md §4.2 (Identidad y acceso) y §8.1 (Auditoría).
-- Solo se migra hacia adelante; cualquier corrección se hace con una migración nueva.
-- El prefijo numérico de 13 dígitos (epoch ms) es el que exige node-pg-migrate (D-09).

-- ─────────────────────────────────────────────────────────────────────────────
-- Catálogo de roles (§5). Es estructura, no dato de demostración: por eso se
-- siembra aquí y no en el script de semilla.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rol (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      TEXT NOT NULL,
  descripcion TEXT,
  CONSTRAINT rol_nombre_check CHECK (
    nombre IN (
      'ESTUDIANTE',
      'DOCENTE',
      'ADMIN_ACADEMICO',
      'ADMIN_ESPACIOS',
      'SEGURIDAD',
      'SOPORTE',
      'AUDITOR'
    )
  ),
  CONSTRAINT rol_nombre_unico UNIQUE (nombre)
);

INSERT INTO rol (nombre, descripcion) VALUES
  ('ESTUDIANTE', 'Consulta carnet, notas, horario y aulas'),
  ('DOCENTE', 'Gestiona aulas, actividades y calificaciones'),
  ('ADMIN_ACADEMICO', 'Administra periodos, grupos, asignaturas e inscripciones'),
  ('ADMIN_ESPACIOS', 'Administra edificios, pisos, salones y asignación de horarios'),
  ('SEGURIDAD', 'Valida el acceso con el modo validador'),
  ('SOPORTE', 'Gestiona incidencias y revoca dispositivos'),
  ('AUDITOR', 'Solo lectura de eventos de auditoría')
ON CONFLICT (nombre) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Usuario. `programa_id` queda sin FK hasta la migración de estructura académica
-- (Fase 1), porque la tabla `programa` todavía no existe.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS usuario (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_firebase        TEXT NOT NULL,
  nombres             TEXT NOT NULL,
  apellidos           TEXT NOT NULL,
  correo              TEXT NOT NULL,
  documento           TEXT,
  codigo_institucional TEXT,
  programa_id         UUID,
  foto_key            TEXT,
  estado              TEXT NOT NULL DEFAULT 'ACTIVO',
  creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT usuario_uid_firebase_unico UNIQUE (uid_firebase),
  CONSTRAINT usuario_correo_unico UNIQUE (correo),
  CONSTRAINT usuario_documento_unico UNIQUE (documento),
  CONSTRAINT usuario_codigo_unico UNIQUE (codigo_institucional),
  CONSTRAINT usuario_estado_check CHECK (estado IN ('ACTIVO', 'INACTIVO'))
);

CREATE INDEX IF NOT EXISTS idx_usuario_programa ON usuario (programa_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Relación N–M usuario ↔ rol (§4.2). Un usuario puede tener varios roles.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS usuario_rol (
  usuario_id   UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  rol_id       UUID NOT NULL REFERENCES rol (id) ON DELETE RESTRICT,
  asignado_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
  asignado_por UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  PRIMARY KEY (usuario_id, rol_id)
);

CREATE INDEX IF NOT EXISTS idx_usuario_rol_rol ON usuario_rol (rol_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Auditoría (§8.1). Campos exactos: id, timestamp, actor_id, accion, recurso,
-- resultado. No se añaden campos adicionales. `timestamp` lo fija el emisor:
-- en validaciones offline es la hora del validador, no la del servidor.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS evento_auditoria (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_id  UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  accion    TEXT NOT NULL,
  recurso   TEXT NOT NULL,
  resultado TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_evento_auditoria_timestamp ON evento_auditoria (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_evento_auditoria_actor ON evento_auditoria (actor_id);
CREATE INDEX IF NOT EXISTS idx_evento_auditoria_accion ON evento_auditoria (accion);

COMMENT ON TABLE usuario IS 'Personas de la muestra (estudiantes, docentes, personal). §4.2';
COMMENT ON COLUMN usuario.uid_firebase IS 'UID de Firebase Authentication; se enlaza en el seed (Fase 1).';
COMMENT ON COLUMN usuario.programa_id IS 'FK a programa; se añade en la migración de estructura académica.';
COMMENT ON TABLE evento_auditoria IS 'Auditoría de solo lectura para el rol AUDITOR. §8.1';
COMMENT ON COLUMN evento_auditoria.timestamp IS 'Hora del evento en su origen (validador offline incluido).';
