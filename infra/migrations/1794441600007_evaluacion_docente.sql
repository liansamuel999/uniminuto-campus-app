-- 1794441600007 · Evaluación docente (Fase 4)
-- Referencias: arquitectura.md §4.2 (tabla `evaluacion_docente`), §5 (matriz RBAC) y D-49.

CREATE TABLE IF NOT EXISTS evaluacion_docente (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inscripcion_id UUID NOT NULL REFERENCES inscripcion (id) ON DELETE CASCADE,
  docente_id     UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  respuestas     JSONB NOT NULL,
  comentario     TEXT,
  enviada_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Una evaluación por inscripción (§4.2).
  CONSTRAINT evaluacion_unica UNIQUE (inscripcion_id)
);

CREATE INDEX IF NOT EXISTS idx_evaluacion_docente ON evaluacion_docente (docente_id, enviada_en DESC);

COMMENT ON TABLE evaluacion_docente IS 'Evaluación del docente por parte del estudiante; una por inscripción (§4.2).';
COMMENT ON COLUMN evaluacion_docente.respuestas IS 'Escala 1–5 por criterio: dominio, claridad, metodologia, evaluacion y acompanamiento.';
