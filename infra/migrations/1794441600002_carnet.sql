-- 1794441600002 · Carnet digital, dispositivos vinculados y auditoría de accesos (Fase 2)
-- Referencias: arquitectura.md §4.2 (carnet, dispositivo, certificado_carnet, lista_revocacion),
-- §6.1 (cadena de confianza ES256) y §8.1 (eventos auditables).

CREATE TABLE IF NOT EXISTS carnet (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  codigo_barras TEXT NOT NULL,
  estado        TEXT NOT NULL DEFAULT 'ACTIVO',
  vigente_hasta DATE NOT NULL,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT carnet_codigo_unico UNIQUE (codigo_barras),
  CONSTRAINT carnet_estado_check CHECK (estado IN ('ACTIVO', 'SUSPENDIDO', 'VENCIDO'))
);

CREATE INDEX IF NOT EXISTS idx_carnet_usuario ON carnet (usuario_id);

CREATE TABLE IF NOT EXISTS dispositivo (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carnet_id          UUID NOT NULL REFERENCES carnet (id) ON DELETE RESTRICT,
  nombre_dispositivo TEXT NOT NULL,
  clave_publica_jwk  JSONB NOT NULL,
  huella             TEXT NOT NULL,
  estado             TEXT NOT NULL DEFAULT 'ACTIVO',
  vinculado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  revocado_en        TIMESTAMPTZ,
  revocado_por       UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  CONSTRAINT dispositivo_estado_check CHECK (estado IN ('ACTIVO', 'REVOCADO')),
  CONSTRAINT dispositivo_huella_unica UNIQUE (huella)
);

-- Regla del documento: un solo dispositivo ACTIVO por carnet.
CREATE UNIQUE INDEX IF NOT EXISTS dispositivo_activo_unico
  ON dispositivo (carnet_id) WHERE estado = 'ACTIVO';

CREATE INDEX IF NOT EXISTS idx_dispositivo_carnet ON dispositivo (carnet_id);

CREATE TABLE IF NOT EXISTS certificado_carnet (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dispositivo_id  UUID NOT NULL REFERENCES dispositivo (id) ON DELETE RESTRICT,
  kid_institucional TEXT NOT NULL,
  emitido_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expira_en       TIMESTAMPTZ NOT NULL,
  jwt_firmado     TEXT NOT NULL,
  CONSTRAINT certificado_unico_por_emision UNIQUE (dispositivo_id, emitido_en)
);

CREATE INDEX IF NOT EXISTS idx_certificado_dispositivo ON certificado_carnet (dispositivo_id, emitido_en DESC);

CREATE TABLE IF NOT EXISTS lista_revocacion (
  carnet_id UUID PRIMARY KEY REFERENCES carnet (id) ON DELETE CASCADE,
  motivo    TEXT NOT NULL,
  desde     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE dispositivo IS 'Llaves públicas de los teléfonos autorizados; un ACTIVO por carnet (§6.1).';
COMMENT ON COLUMN dispositivo.huella IS 'Thumbprint de la JWK pública (RFC 7638) para deduplicar.';
COMMENT ON TABLE certificado_carnet IS 'JWT firmado por la clave institucional ES256, vida de 30 días.';
COMMENT ON TABLE lista_revocacion IS 'Fuente de la lista que descargan los validadores (D-32).';
