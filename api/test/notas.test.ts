import { describe, expect, it } from 'vitest';
import { calcularDefinitiva, calcularNotaCorte, redondear2 } from '../src/lib/notas.js';
import type { ActividadCalificada, CorteConActividades } from '../src/lib/notas.js';

function actividad(peso: number, nota: number | null, titulo = 'Actividad'): ActividadCalificada {
  return { actividadId: titulo, titulo, peso, notaMaxima: 5, nota };
}

describe('cálculo de notas (§4.2, D-44)', () => {
  it('redondea a 2 decimales con mitad hacia arriba', () => {
    expect(redondear2(4.005)).toBe(4.01);
    expect(redondear2(3.3333)).toBe(3.33);
  });

  it('ponderación simple: (4.0×50 + 5.0×50) / 100 = 4.5', () => {
    expect(calcularNotaCorte([actividad(50, 4.0), actividad(50, 5.0)])).toBe(4.5);
  });

  it('excluye del denominador las actividades sin calificar', () => {
    expect(calcularNotaCorte([actividad(50, 4.0), actividad(50, null)])).toBe(4.0);
  });

  it('sin actividades calificadas la nota de corte es nula', () => {
    expect(calcularNotaCorte([actividad(50, null)])).toBeNull();
    expect(calcularNotaCorte([])).toBeNull();
  });

  it('la definitiva pondera los cortes y trata como 0 el corte sin nota', () => {
    const cortes: CorteConActividades[] = [
      { corteId: 'c1', numero: 1, peso: 30, actividades: [actividad(50, 4.5), actividad(50, null)] },
      { corteId: 'c2', numero: 2, peso: 30, actividades: [actividad(100, null)] },
      { corteId: 'c3', numero: 3, peso: 40, actividades: [actividad(100, 3.0)] },
    ];

    // 4.5×0.30 + 0×0.30 + 3.0×0.40 = 1.35 + 0 + 1.2 = 2.55
    expect(calcularDefinitiva(cortes)).toBe(2.55);
  });

  it('redondea el resultado final a 2 decimales', () => {
    const cortes: CorteConActividades[] = [
      { corteId: 'c1', numero: 1, peso: 30, actividades: [actividad(100, 4.33)] },
      { corteId: 'c2', numero: 2, peso: 30, actividades: [actividad(100, 4.33)] },
      { corteId: 'c3', numero: 3, peso: 40, actividades: [actividad(100, 4.33)] },
    ];
    expect(calcularDefinitiva(cortes)).toBe(4.33);
  });
});
