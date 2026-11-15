-- 1794441600009 · Formatos de archivo permitidos por actividad (mejora de Fase 3/6)
-- Permite que un docente limite los adjuntos de una tarea a ciertas extensiones (p. ej. PDF o PNG).

ALTER TABLE actividad ADD COLUMN IF NOT EXISTS formatos_permitidos TEXT[];

COMMENT ON COLUMN actividad.formatos_permitidos IS
  'Extensiones permitidas para los adjuntos de la entrega (vacío = todas las de la demo).';
