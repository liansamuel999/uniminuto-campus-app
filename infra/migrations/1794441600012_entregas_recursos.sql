-- 1794441600012 · Correcciones de experiencia (Fase 6):
--   * El estudiante puede reemplazar su entrega mientras la actividad no haya cerrado.
--   * Las actividades pueden tener archivos/materiales propios (no solo las unidades del aula).
--
-- Referencias: arquitectura.md §6.2/§6.3, D-86 (reentrega y recursos de actividad).

ALTER TABLE entrega
  ADD COLUMN IF NOT EXISTS actualizada_en TIMESTAMPTZ;

COMMENT ON COLUMN entrega.actualizada_en IS
  'Momento de la última reentrega del estudiante mientras la actividad seguía abierta.';

CREATE TABLE IF NOT EXISTS actividad_recurso (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actividad_id UUID NOT NULL REFERENCES actividad (id) ON DELETE CASCADE,
  objeto_key  TEXT NOT NULL,
  nombre      TEXT NOT NULL,
  mime        TEXT,
  tamano      BIGINT,
  subido_por  UUID REFERENCES usuario (id) ON DELETE SET NULL,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_actividad_recurso ON actividad_recurso (actividad_id);

COMMENT ON TABLE actividad_recurso IS
  'Archivos/materiales adjuntos a una actividad (tarea, examen o foro), independientes de los contenidos de la unidad.';
