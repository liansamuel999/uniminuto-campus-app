-- 1794441600006 · Correo simulado (§6.2)

CREATE TABLE IF NOT EXISTS correo_simulado (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anuncio_id   TEXT NOT NULL,
  destinatario UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  asunto       TEXT NOT NULL,
  cuerpo       TEXT NOT NULL,
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT correo_unico UNIQUE (anuncio_id, destinatario)
);

CREATE INDEX IF NOT EXISTS idx_correo_destinatario ON correo_simulado (destinatario, creado_en DESC);

COMMENT ON TABLE correo_simulado IS 'Sustituye al envío real de correo; una fila por estudiante y anuncio.';
