-- 1794441600010 · Experiencia por rol: contenidos generales, revisión de cuestionarios y
-- planificación automática de salones (Fase 6, correcciones de la muestra).
--
-- Amplía los tipos de contenido del aula (archivos generales, imágenes, presentaciones, hojas
-- de cálculo), permite que el docente habilite la revisión de respuestas del cuestionario y
-- marca qué asignaturas necesitan equipos (laboratorio) para que el planificador elija salón.

ALTER TABLE contenido DROP CONSTRAINT IF EXISTS contenido_tipo_check;
ALTER TABLE contenido ADD CONSTRAINT contenido_tipo_check
  CHECK (tipo IN (
    'PDF', 'VIDEO', 'ENLACE', 'ANUNCIO',
    'IMAGEN', 'DOCUMENTO', 'PRESENTACION', 'HOJA_CALCULO', 'ARCHIVO'
  ));

ALTER TABLE actividad
  ADD COLUMN IF NOT EXISTS revision_permitida BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN actividad.revision_permitida IS
  'Si es true, el estudiante puede revisar después de enviar qué opciones acertó (corrección del cuestionario).';

ALTER TABLE asignatura
  ADD COLUMN IF NOT EXISTS requiere_laboratorio BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN asignatura.requiere_laboratorio IS
  'El planificador de horarios solo asigna salones tipo LABORATORIO a estas asignaturas.';

CREATE INDEX IF NOT EXISTS idx_horario_grupo ON horario (grupo_id);
