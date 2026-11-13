-- 1794441600005 · Metadatos de archivos del datalake (§6.3)

CREATE TABLE IF NOT EXISTS archivo (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  objeto_key  TEXT NOT NULL,
  mime        TEXT NOT NULL,
  tamano      BIGINT NOT NULL,
  subido_por  UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT archivo_key_unica UNIQUE (objeto_key),
  CONSTRAINT archivo_tamano_check CHECK (tamano > 0)
);

CREATE INDEX IF NOT EXISTS idx_archivo_usuario ON archivo (subido_por);

COMMENT ON TABLE archivo IS 'Metadatos del objeto; el binario vive en MinIO/R2 y nunca es público.';
