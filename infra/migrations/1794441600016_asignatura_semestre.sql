-- 1794441600016 · Semestre de la asignatura para organizar la oferta académica.
--
-- El panel de inscripciones necesita filtrar por carrera y semestre antes de mostrar los cursos;
-- el dato vive en la asignatura y no cambia la identidad del curso.

ALTER TABLE asignatura
  ADD COLUMN IF NOT EXISTS semestre SMALLINT NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_asignatura_programa_semestre
  ON asignatura (programa_id, semestre);
