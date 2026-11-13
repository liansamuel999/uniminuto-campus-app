/**
 * Roles de la matriz RBAC (§5). La autorización fina se aplica en cada ruta de la API
 * y en las reglas de Firestore; nunca solo en la interfaz.
 */
export const ROLES = [
  'ESTUDIANTE',
  'DOCENTE',
  'ADMIN_ACADEMICO',
  'ADMIN_ESPACIOS',
  'SEGURIDAD',
  'SOPORTE',
  'AUDITOR',
] as const;

export type Rol = (typeof ROLES)[number];

/** Comprueba si un valor arbitrario es un rol conocido. */
export function esRol(valor: string): valor is Rol {
  return (ROLES as readonly string[]).includes(valor);
}

/** `true` si el usuario tiene al menos uno de los roles exigidos (D-21). */
export function tieneAlgunRol(rolesDelUsuario: readonly string[], requeridos: readonly Rol[]): boolean {
  if (requeridos.length === 0) return true;
  return requeridos.some((rol) => rolesDelUsuario.includes(rol));
}
