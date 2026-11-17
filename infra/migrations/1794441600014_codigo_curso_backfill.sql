-- 1794441600014 · Backfill e índice único de `grupo.codigo_curso` (continuación de 0013).

UPDATE grupo
SET codigo_curso = 'CUR-' || UPPER(SUBSTRING(REPLACE(id::text, '-', '') FROM 1 FOR 6))
WHERE codigo_curso IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_grupo_codigo_curso ON grupo (codigo_curso);

COMMENT ON COLUMN grupo.codigo_curso IS
  'Código único del curso (NRC o equivalente). Es lo que se muestra al estudiante y al docente; numero_grupo queda como detalle interno.';
