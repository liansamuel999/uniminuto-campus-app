/**
 * Fórmulas de calificación (§4.2, D-44):
 *   nota de corte = Σ(nota × peso) / Σ(pesos de actividades calificadas)
 *   definitiva     = Σ(nota de corte × peso del corte), los cortes sin nota cuentan 0
 */

export interface ActividadCalificada {
  actividadId: string;
  titulo: string;
  peso: number;
  notaMaxima: number;
  nota: number | null;
  retroalimentacion?: string | null;
}

export interface CorteConActividades {
  corteId: string;
  numero: number;
  peso: number;
  actividades: ActividadCalificada[];
}

export interface ResumenNotas {
  cortes: Array<{ corteId: string; numero: number; peso: number; nota: number | null }>;
  definitiva: number;
}

/** Redondeo a 2 decimales, mitad hacia arriba (D-44). */
export function redondear2(valor: number): number {
  return Math.round((valor + Number.EPSILON) * 100) / 100;
}

/** Nota de un corte; `null` si ninguna actividad del corte tiene nota. */
export function calcularNotaCorte(actividades: readonly ActividadCalificada[]): number | null {
  const calificadas = actividades.filter((actividad) => actividad.nota !== null);
  const sumaPesos = calificadas.reduce((total, actividad) => total + actividad.peso, 0);
  if (calificadas.length === 0 || sumaPesos === 0) return null;

  const suma = calificadas.reduce((total, actividad) => total + (actividad.nota ?? 0) * actividad.peso, 0);
  return redondear2(suma / sumaPesos);
}

/** Definitiva del periodo; los cortes sin nota cuentan como 0. */
export function calcularDefinitiva(cortes: readonly CorteConActividades[]): number {
  const total = cortes.reduce((acumulado, corte) => {
    const nota = calcularNotaCorte(corte.actividades) ?? 0;
    return acumulado + (nota * corte.peso) / 100;
  }, 0);
  return redondear2(total);
}

export function resumirNotas(cortes: readonly CorteConActividades[]): ResumenNotas {
  return {
    cortes: cortes.map((corte) => ({
      corteId: corte.corteId,
      numero: corte.numero,
      peso: corte.peso,
      nota: calcularNotaCorte(corte.actividades),
    })),
    definitiva: calcularDefinitiva(cortes),
  };
}
