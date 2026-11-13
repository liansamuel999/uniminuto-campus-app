/** Autocalificación de cuestionarios (§6.4, D-46) y validación de adjuntos (§6.3). */

export interface PreguntaCorregible {
  id: string;
  opciones: Array<{ id: string; esCorrecta: boolean }>;
}

export interface ResultadoIntento {
  puntaje: number;
  correctas: number;
  total: number;
}

/** Nota = (correctas / total) × nota máxima, con 2 decimales. */
export function calificarIntento(
  preguntas: readonly PreguntaCorregible[],
  respuestas: Record<string, readonly string[]>,
  notaMaxima: number,
): ResultadoIntento {
  if (preguntas.length === 0) return { puntaje: 0, correctas: 0, total: 0 };

  let correctas = 0;
  for (const pregunta of preguntas) {
    const correctasDeLaPregunta = pregunta.opciones
      .filter((opcion) => opcion.esCorrecta)
      .map((opcion) => opcion.id)
      .sort();
    const marcadas = [...(respuestas[pregunta.id] ?? [])].sort();
    if (
      correctasDeLaPregunta.length === marcadas.length &&
      correctasDeLaPregunta.every((id, indice) => id === marcadas[indice])
    ) {
      correctas += 1;
    }
  }

  const puntaje = Math.round(((correctas / preguntas.length) * notaMaxima + Number.EPSILON) * 100) / 100;
  return { puntaje, correctas, total: preguntas.length };
}

export const MIMES_PERMITIDOS = new Set([
  'application/pdf',
  'image/png',
  'image/jpeg',
  'image/webp',
  'video/mp4',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/zip',
  'text/plain',
]);

export interface ValidacionArchivo {
  valido: boolean;
  motivo?: string;
}

export function validarArchivo(params: {
  mime: string;
  tamano: number;
  maximoBytes: number;
}): ValidacionArchivo {
  if (!MIMES_PERMITIDOS.has(params.mime)) {
    return { valido: false, motivo: `Tipo de archivo no permitido (${params.mime})` };
  }
  if (params.tamano <= 0) return { valido: false, motivo: 'El archivo está vacío' };
  if (params.tamano > params.maximoBytes) {
    return { valido: false, motivo: 'El archivo supera el límite de 50 MB' };
  }
  return { valido: true };
}
