-- 1794441600008 · Incidencias (Fase 5)
-- Referencias: arquitectura.md §5 (matriz RBAC) y D-50.

CREATE TABLE IF NOT EXISTS incidencia (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  descripcion   TEXT NOT NULL,
  estado        TEXT NOT NULL DEFAULT 'ABIERTA',
  resolucion    TEXT,
  atendida_por  UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  creada_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT incidencia_estado_check CHECK (estado IN ('ABIERTA', 'EN_PROCESO', 'RESUELTA', 'CERRADA'))
);

CREATE INDEX IF NOT EXISTS idx_incidencia_usuario ON incidencia (usuario_id, creada_en DESC);
CREATE INDEX IF NOT EXISTS idx_incidencia_estado ON incidencia (estado, creada_en DESC);

COMMENT ON TABLE incidencia IS 'Reporte de incidencias del usuario; Soporte las gestiona (§5, D-50).';
COMMENT ON COLUMN incidencia.resolucion IS 'Nota de cierre que escribe Soporte al resolverla.';
