-- 1794441600004 · Aulas Virtuales, actividades y calificaciones (Fase 3)
-- Referencias: arquitectura.md §4.2 (Aulas Virtuales, Calificaciones) y §6.4.

CREATE TABLE IF NOT EXISTS corte (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id         UUID NOT NULL REFERENCES grupo (id) ON DELETE RESTRICT,
  numero           SMALLINT NOT NULL,
  peso_porcentual  NUMERIC(5, 2) NOT NULL,
  CONSTRAINT corte_unico UNIQUE (grupo_id, numero),
  CONSTRAINT corte_numero_check CHECK (numero BETWEEN 1 AND 3),
  CONSTRAINT corte_peso_check CHECK (peso_porcentual > 0 AND peso_porcentual <= 100)
);

CREATE TABLE IF NOT EXISTS aula (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id    UUID NOT NULL REFERENCES grupo (id) ON DELETE RESTRICT,
  nombre      TEXT NOT NULL,
  descripcion TEXT,
  CONSTRAINT aula_grupo_unico UNIQUE (grupo_id)
);

CREATE TABLE IF NOT EXISTS unidad (
  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aula_id  UUID NOT NULL REFERENCES aula (id) ON DELETE CASCADE,
  numero   SMALLINT NOT NULL,
  titulo   TEXT NOT NULL,
  CONSTRAINT unidad_unica UNIQUE (aula_id, numero)
);

CREATE TABLE IF NOT EXISTS contenido (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unidad_id   UUID NOT NULL REFERENCES unidad (id) ON DELETE CASCADE,
  tipo        TEXT NOT NULL,
  titulo      TEXT NOT NULL,
  descripcion TEXT,
  objeto_key  TEXT,
  url_externa TEXT,
  mime        TEXT,
  tamano      BIGINT,
  CONSTRAINT contenido_tipo_check CHECK (tipo IN ('PDF', 'VIDEO', 'ENLACE', 'ANUNCIO'))
);

CREATE INDEX IF NOT EXISTS idx_contenido_unidad ON contenido (unidad_id);

CREATE TABLE IF NOT EXISTS actividad (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unidad_id       UUID NOT NULL REFERENCES unidad (id) ON DELETE CASCADE,
  tipo            TEXT NOT NULL,
  titulo          TEXT NOT NULL,
  instrucciones   TEXT,
  abre_en         TIMESTAMPTZ,
  cierra_en       TIMESTAMPTZ,
  corte_id        UUID NOT NULL REFERENCES corte (id) ON DELETE RESTRICT,
  peso_porcentual NUMERIC(5, 2) NOT NULL,
  nota_maxima     NUMERIC(3, 1) NOT NULL DEFAULT 5.0,
  CONSTRAINT actividad_tipo_check CHECK (tipo IN ('TAREA', 'CUESTIONARIO', 'FORO')),
  CONSTRAINT actividad_peso_check CHECK (peso_porcentual > 0 AND peso_porcentual <= 100),
  CONSTRAINT actividad_nota_maxima_check CHECK (nota_maxima > 0 AND nota_maxima <= 5)
);

CREATE INDEX IF NOT EXISTS idx_actividad_unidad ON actividad (unidad_id);

CREATE TABLE IF NOT EXISTS pregunta (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actividad_id UUID NOT NULL REFERENCES actividad (id) ON DELETE CASCADE,
  enunciado    TEXT NOT NULL,
  tipo         TEXT NOT NULL DEFAULT 'UNICA',
  orden        SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT pregunta_tipo_check CHECK (tipo IN ('UNICA', 'MULTIPLE'))
);

CREATE TABLE IF NOT EXISTS opcion_respuesta (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pregunta_id UUID NOT NULL REFERENCES pregunta (id) ON DELETE CASCADE,
  texto       TEXT NOT NULL,
  es_correcta BOOLEAN NOT NULL DEFAULT false,
  orden       SMALLINT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS intento_cuestionario (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actividad_id UUID NOT NULL REFERENCES actividad (id) ON DELETE RESTRICT,
  estudiante_id UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  respuestas   JSONB NOT NULL,
  puntaje      NUMERIC(3, 2) NOT NULL,
  enviado_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT intento_unico UNIQUE (actividad_id, estudiante_id)
);

CREATE TABLE IF NOT EXISTS entrega (
  id                  UUID PRIMARY KEY,
  actividad_id        UUID NOT NULL REFERENCES actividad (id) ON DELETE RESTRICT,
  estudiante_id       UUID NOT NULL REFERENCES usuario (id) ON DELETE RESTRICT,
  texto               TEXT,
  adjuntos            JSONB NOT NULL DEFAULT '[]',
  creada_en_cliente   TIMESTAMPTZ NOT NULL,
  recibida_en_servidor TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado              TEXT NOT NULL,
  CONSTRAINT entrega_estado_check CHECK (estado IN ('ENVIADA', 'TARDIA')),
  CONSTRAINT entrega_unica UNIQUE (actividad_id, estudiante_id)
);

CREATE TABLE IF NOT EXISTS calificacion (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actividad_id     UUID NOT NULL REFERENCES actividad (id) ON DELETE RESTRICT,
  inscripcion_id   UUID NOT NULL REFERENCES inscripcion (id) ON DELETE RESTRICT,
  nota             NUMERIC(3, 2) NOT NULL,
  retroalimentacion TEXT,
  calificada_por   UUID REFERENCES usuario (id) ON DELETE RESTRICT,
  calificada_en    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT calificacion_unica UNIQUE (actividad_id, inscripcion_id),
  CONSTRAINT calificacion_nota_check CHECK (nota >= 0 AND nota <= 5)
);

CREATE TABLE IF NOT EXISTS nota_corte (
  inscripcion_id  UUID NOT NULL REFERENCES inscripcion (id) ON DELETE CASCADE,
  corte_id        UUID NOT NULL REFERENCES corte (id) ON DELETE CASCADE,
  nota_calculada  NUMERIC(3, 2),
  actualizada_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (inscripcion_id, corte_id)
);

COMMENT ON TABLE aula IS 'Aula virtual de un grupo; una por grupo (§4.2).';
COMMENT ON TABLE entrega IS 'La clave es el UUID generado en el cliente: idempotencia de POST /entregas.';
COMMENT ON COLUMN entrega.estado IS 'ENVIADA si creada_en_cliente <= cierra_en; TARDIA si llegó después.';
