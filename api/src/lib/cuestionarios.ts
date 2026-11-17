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
  'image/gif',
  'image/svg+xml',
  'video/mp4',
  'video/webm',
  'audio/mpeg',
  'audio/wav',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.oasis.opendocument.text',
  'application/vnd.oasis.opendocument.spreadsheet',
  'application/vnd.oasis.opendocument.presentation',
  'application/rtf',
  'application/zip',
  'text/plain',
  'text/csv',
  'text/html',
  'application/json',
  // Archivos generales del aula: el editor acepta cualquier archivo y el navegador no siempre
  // informa el MIME; en la muestra se permite el genérico (corrección de la muestra).
  'application/octet-stream',
]);

// Extensiones aceptadas aunque el navegador no informe un MIME conocido (ZIP/RAR/7z, Packet
// Tracer, Wireshark, código fuente, etc.). Para la muestra se prioriza que el docente pueda subir
// material de clase real; solo se bloquean ejecutables.
export const EXTENSIONES_PERMITIDAS = new Set([
  'pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'bmp', 'tiff',
  'mp4', 'webm', 'mov', 'avi', 'mkv',
  'mp3', 'wav', 'ogg', 'm4a',
  'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'vsdx', 'drawio',
  'txt', 'csv', 'md', 'html', 'css', 'xml', 'json', 'yaml', 'yml', 'sql',
  'py', 'js', 'ts', 'java', 'c', 'cpp', 'h', 'cs', 'php', 'ipynb',
  'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2',
  'pkt', 'pka', 'pcap', 'pcapng',
  'psd', 'ai', 'fig', 'sketch', 'jar',
]);

export const EXTENSIONES_BLOQUEADAS = new Set([
  'exe', 'msi', 'bat', 'cmd', 'com', 'scr', 'ps1', 'vbs', 'hta', 'cpl', 'msc', 'reg',
]);

export interface ValidacionArchivo {
  valido: boolean;
  motivo?: string;
}

export function validarArchivo(params: {
  mime: string;
  tamano: number;
  maximoBytes: number;
  nombre?: string;
}): ValidacionArchivo {
  if (params.tamano <= 0) return { valido: false, motivo: 'El archivo está vacío' };
  if (params.tamano > params.maximoBytes) {
    return { valido: false, motivo: 'El archivo supera el límite de 50 MB' };
  }
  const extension = params.nombre?.split('.').pop()?.toLowerCase() ?? '';
  if (extension && EXTENSIONES_BLOQUEADAS.has(extension)) {
    return { valido: false, motivo: 'No se permiten archivos ejecutables por seguridad' };
  }
  if (MIMES_PERMITIDOS.has(params.mime)) return { valido: true };
  if (extension && EXTENSIONES_PERMITIDAS.has(extension)) return { valido: true };
  if (params.mime === 'application/octet-stream' && extension && !EXTENSIONES_BLOQUEADAS.has(extension)) {
    return { valido: true };
  }
  return {
    valido: false,
    motivo: `Tipo de archivo no permitido (${params.mime || extension || 'desconocido'})`,
  };
}
