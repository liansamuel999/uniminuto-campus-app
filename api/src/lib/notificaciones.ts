import { getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

/**
 * Aviso que la API deja en el árbol `notificaciones/{uid}/items` de Firestore (§6.4, D-42).
 * La app lo pinta como bandeja interna con badge; el dueño solo puede marcar `leida`.
 */
export interface AvisoNotificacion {
  uid: string;
  titulo: string;
  cuerpo: string;
  tipo: 'NOTA' | 'ANUNCIO' | 'FORO';
}

/**
 * Deja una notificación en Firestore para el usuario indicado (§6.4).
 *
 * Es *best-effort*: si el Admin SDK no está inicializado (arranque sin cuenta de servicio)
 * o Firebase no responde, la operación de negocio no falla; solo se pierde el aviso.
 */
export async function notificarAlUsuario(aviso: AvisoNotificacion): Promise<boolean> {
  const app = getApps()[0];
  if (!app) return false;
  try {
    await getFirestore(app)
      .collection('notificaciones')
      .doc(aviso.uid)
      .collection('items')
      .add({
        titulo: aviso.titulo,
        cuerpo: aviso.cuerpo,
        tipo: aviso.tipo,
        leida: false,
        creado_en: new Date().toISOString(),
      });
    return true;
  } catch {
    return false;
  }
}
