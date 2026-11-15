import { getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Pool } from 'pg';

/**
 * Mantiene `foros_index/{foroId}` (D-78): espejo de miembros/docentes del aula dueña del foro.
 *
 * Las reglas de Firestore no pueden autorizar consultas de lista con `resource.data`, así que la
 * membresía se resuelve por el id del foro. Si Firebase no está disponible, el foro igual se crea
 * en SQL y el índice se generará la próxima vez que se ejecute la semilla.
 */
export async function sincronizarIndiceForo(
  pool: Pool,
  foroId: string,
  aulaId: string,
): Promise<void> {
  const app = getApps()[0];
  if (!app) return;
  try {
    const resultado = await pool.query<{
      miembros: string[] | null;
      docentes: string[] | null;
    }>(
      `SELECT
         (SELECT COALESCE(array_agg(u.uid_firebase), '{}')
          FROM inscripcion i JOIN usuario u ON u.id = i.estudiante_id
          WHERE i.grupo_id = g.id AND i.estado = 'ACTIVA') AS miembros,
         (SELECT COALESCE(array_agg(u.uid_firebase), '{}')
          FROM usuario u WHERE u.id = g.docente_id) AS docentes
       FROM aula au JOIN grupo g ON g.id = au.grupo_id
       WHERE au.id = $1`,
      [aulaId],
    );
    const fila = resultado.rows[0];
    await getFirestore(app)
      .doc(`foros_index/${foroId}`)
      .set(
        {
          aula_id: aulaId,
          miembros: fila?.miembros ?? [],
          docentes: fila?.docentes ?? [],
        },
        { merge: true },
      );
  } catch {
    // Best-effort: la semilla vuelve a sincronizar los índices.
  }
}

export async function eliminarIndiceForo(foroId: string): Promise<void> {
  const app = getApps()[0];
  if (!app) return;
  try {
    await getFirestore(app).doc(`foros_index/${foroId}`).delete();
  } catch {
    // Best-effort.
  }
}
