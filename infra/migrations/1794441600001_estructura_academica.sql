-- 1794441600001 · Estructura académica y del campus (Fase 1)
-- Referencias: arquitectura.md §4.2 (Estructura académica, Horarios y espacios) y §4.3.
-- Se crean aquí las tablas que necesita la semilla de la Fase 1; los endpoints y la UI de
-- espacios/horarios llegan en la Fase 4.

-- ─────────────────────────────────────────────────────────────────────────────
-- Programa académico y su vínculo con el usuario (FK pendiente desde 0001).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS programa (
  id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL,
  CONSTRAINT programa_nombre_unico UNIQUE (nombre)
);

ALTER TABLE usuario
  ADD CONSTRAINT usuario_programa_fk FOREIGN KEY (programa_id) REFERENCES programa (id) ON DELETE RESTRICT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Periodo, asignatura, grupo e inscripción.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS periodo (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo       TEXT NOT NULL,
  tipo         TEXT NOT NULL DEFAULT 'SEMESTRAL',
  fecha_inicio DATE NOT NULL,
  fecha_fin    DATE NOT NULL,
  activo       BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT periodo_codigo_unico UNIQUE (codigo),
  CONSTRAINT periodo_tipo_check CHECK (tipo IN ('SEMESTRAL', 'CUATRIMESTRAL')),
  CONSTRAINT periodo_fechas_check CHECK (fecha_fin > fecha_inicio)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_periodo_activo ON periodo (activo) WHERE activo = true;

CREATE TABLE IF NOT EXISTS asignatura (
  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo   TEXT NOT NULL,
  nombre   TEXT NOT NULL,
  creditos SMALLINT NOT NULL,
  CONSTRAINT asignatura_codigo_unico UNIQUE (codigo),
  CONSTRAINT asignatura_creditos_check CHECK (creditos > 0)
);

CREATE TABLE IF NOT EXISTS grupo (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asignatura_id UUID NOT NULL REFERENCES asignatura (id) ON DELETE RESTRICT,
  periodo_id    UUID NOT NULL REFERENCES periodo (id) ON DELETE RESTRICT,
  docente_id    UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  numero_grupo  TEXT NOT NULL DEFAULT '01',
  CONSTRAINT grupo_unico UNIQUE (asignatura_id, periodo_id, numero_grupo)
);

CREATE INDEX IF NOT EXISTS idx_grupo_periodo ON grupo (periodo_id);
CREATE INDEX IF NOT EXISTS idx_grupo_docente ON grupo (docente_id);

CREATE TABLE IF NOT EXISTS inscripcion (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estudiante_id UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  grupo_id      UUID NOT NULL REFERENCES grupo (id) ON DELETE RESTRICT,
  estado        TEXT NOT NULL DEFAULT 'ACTIVA',
  inscrita_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT inscripcion_unica UNIQUE (estudiante_id, grupo_id),
  CONSTRAINT inscripcion_estado_check CHECK (estado IN ('ACTIVA', 'RETIRADA', 'APROBADA', 'REPROBADA'))
);

CREATE INDEX IF NOT EXISTS idx_inscripcion_grupo ON inscripcion (grupo_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Campus: edificio → piso → salón (§4.3) y horarios.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS edificio (
  id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT NOT NULL,
  nombre TEXT NOT NULL,
  sede   TEXT NOT NULL DEFAULT 'CALLE_80',
  CONSTRAINT edificio_codigo_unico UNIQUE (codigo),
  CONSTRAINT edificio_sede_check CHECK (sede IN ('CALLE_80'))
);

CREATE TABLE IF NOT EXISTS piso (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  edificio_id UUID NOT NULL REFERENCES edificio (id) ON DELETE RESTRICT,
  numero      SMALLINT NOT NULL,
  tipo        TEXT NOT NULL,
  CONSTRAINT piso_unico UNIQUE (edificio_id, numero),
  CONSTRAINT piso_tipo_check CHECK (tipo IN ('ESTUDIANTIL', 'ADMINISTRATIVO')),
  CONSTRAINT piso_numero_check CHECK (numero > 0)
);

CREATE TABLE IF NOT EXISTS salon (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  piso_id   UUID NOT NULL REFERENCES piso (id) ON DELETE RESTRICT,
  codigo    TEXT NOT NULL,
  tipo      TEXT NOT NULL DEFAULT 'AULA',
  capacidad SMALLINT NOT NULL,
  CONSTRAINT salon_codigo_unico UNIQUE (codigo),
  CONSTRAINT salon_tipo_check CHECK (tipo IN ('AULA', 'LABORATORIO', 'OFICINA')),
  CONSTRAINT salon_capacidad_check CHECK (capacidad > 0)
);

CREATE INDEX IF NOT EXISTS idx_salon_piso ON salon (piso_id);

CREATE TABLE IF NOT EXISTS horario (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id    UUID NOT NULL REFERENCES grupo (id) ON DELETE CASCADE,
  salon_id    UUID NOT NULL REFERENCES salon (id) ON DELETE RESTRICT,
  dia_semana  SMALLINT NOT NULL,
  hora_inicio TIME NOT NULL,
  hora_fin    TIME NOT NULL,
  CONSTRAINT horario_dia_check CHECK (dia_semana BETWEEN 1 AND 7),
  CONSTRAINT horario_horas_check CHECK (hora_fin > hora_inicio),
  CONSTRAINT horario_unico UNIQUE (grupo_id, dia_semana, hora_inicio)
);

CREATE INDEX IF NOT EXISTS idx_horario_salon ON horario (salon_id, dia_semana);

COMMENT ON TABLE periodo IS 'Periodo académico; el activo es único (§4.2).';
COMMENT ON TABLE inscripcion IS 'Inscripción de un estudiante a un grupo; alimenta mis-asignaturas y notas.';
COMMENT ON TABLE salon IS 'Salón del campus Calle 80; el código sigue <Edificio>-<Piso><NN> (§4.3).';
COMMENT ON COLUMN horario.dia_semana IS 'ISO-8601: 1 = lunes … 7 = domingo (D-12).';
