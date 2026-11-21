-- 1794441600015 · Mensajería interna, disponibilidad docente, programa de asignatura y analítica.
--
-- Estas estructuras sostienen las mejoras solicitadas sin cambiar el modelo académico existente:
--  * `usuario.turnos_disponibles` permite que el generador de horarios respete mañana/tarde/noche.
--  * `asignatura.programa_id` permite filtrar estudiantes por programa al inscribir.
--  * `mensaje` habilita la bandeja de mensajes entre estudiantes y docentes.
--  * `analitica_ejecucion` y `analitica_metrica` son la capa curada del data lake.

ALTER TABLE asignatura
  ADD COLUMN IF NOT EXISTS programa_id UUID REFERENCES programa(id) ON DELETE SET NULL;

ALTER TABLE usuario
  ADD COLUMN IF NOT EXISTS turnos_disponibles TEXT[] NOT NULL
  DEFAULT ARRAY['MANANA', 'TARDE', 'NOCHE'];

CREATE INDEX IF NOT EXISTS idx_asignatura_programa ON asignatura (programa_id);

CREATE TABLE IF NOT EXISTS mensaje (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  remitente_id UUID NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT,
  destinatario_id UUID NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT,
  asunto TEXT NOT NULL,
  cuerpo TEXT NOT NULL,
  leido BOOLEAN NOT NULL DEFAULT false,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT mensaje_no_autoenvio CHECK (remitente_id <> destinatario_id),
  CONSTRAINT mensaje_asunto_largo CHECK (length(asunto) BETWEEN 1 AND 160),
  CONSTRAINT mensaje_cuerpo_largo CHECK (length(cuerpo) BETWEEN 1 AND 4000)
);

CREATE INDEX IF NOT EXISTS idx_mensaje_destinatario
  ON mensaje (destinatario_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_mensaje_remitente
  ON mensaje (remitente_id, creado_en DESC);

CREATE TABLE IF NOT EXISTS analitica_ejecucion (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  generado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  objeto_key TEXT,
  filas INTEGER NOT NULL DEFAULT 0,
  detalle JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS analitica_metrica (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ejecucion_id UUID NOT NULL REFERENCES analitica_ejecucion(id) ON DELETE CASCADE,
  categoria TEXT NOT NULL,
  clave TEXT NOT NULL,
  etiqueta TEXT NOT NULL,
  valor NUMERIC(14, 4) NOT NULL DEFAULT 0,
  detalle JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_analitica_metrica_ejecucion
  ON analitica_metrica (ejecucion_id, categoria);
