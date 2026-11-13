-- 1794441600003 · Reservaciones de espacios de autorecreación
-- Ampliación aprobada por el cliente sobre la arquitectura: 6 cabinas individuales y 5 salas
-- grupales (3 de 4 personas, 1 de 5 y 1 de 6).

CREATE TABLE IF NOT EXISTS espacio_reservable (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre    TEXT NOT NULL,
  tipo      TEXT NOT NULL,
  capacidad SMALLINT NOT NULL,
  activo    BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT espacio_reservable_nombre_unico UNIQUE (nombre),
  CONSTRAINT espacio_reservable_tipo_check CHECK (tipo IN ('INDIVIDUAL', 'GRUPO')),
  CONSTRAINT espacio_reservable_capacidad_check CHECK (capacidad BETWEEN 1 AND 10)
);

CREATE TABLE IF NOT EXISTS reservacion (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  espacio_id  UUID NOT NULL REFERENCES espacio_reservable (id) ON DELETE RESTRICT,
  usuario_id  UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  inicio      TIMESTAMPTZ NOT NULL,
  fin         TIMESTAMPTZ NOT NULL,
  estado      TEXT NOT NULL DEFAULT 'CONFIRMADA',
  creada_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT reservacion_estado_check CHECK (estado IN ('CONFIRMADA', 'CANCELADA')),
  CONSTRAINT reservacion_rango_check CHECK (fin > inicio),
  CONSTRAINT reservacion_duracion_check CHECK (fin <= inicio + interval '2 hours'),
  CONSTRAINT reservacion_inicio_unico UNIQUE (espacio_id, inicio)
);

CREATE INDEX IF NOT EXISTS idx_reservacion_espacio ON reservacion (espacio_id, inicio);
CREATE INDEX IF NOT EXISTS idx_reservacion_usuario ON reservacion (usuario_id, inicio DESC);

COMMENT ON TABLE espacio_reservable IS 'Cabinas y salas de autorecreación reservables.';
COMMENT ON TABLE reservacion IS 'Reservas de 30 a 120 minutos entre 07:00 y 20:00 (hora Colombia).';
