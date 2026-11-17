-- 1794441600013 · Cada curso (oferta académica) tiene su propio código único de curso.
--
-- En la realidad una asignatura puede ofrecerse en varios cursos a lo largo del tiempo (distintos
-- periodos, docentes o secciones), y cada uno se identifica por su **código de curso** (tipo NRC),
-- no por “grupo 01/02”. `codigo_curso` pasa a ser la identidad visible del curso.
--
-- El backfill y el índice único van en la migración 0014: CockroachDB no permite modificar la
-- misma columna en la transacción en la que se agrega (la columna queda “being backfilled”).

ALTER TABLE grupo ADD COLUMN IF NOT EXISTS codigo_curso TEXT;
