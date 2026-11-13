import { describe, expect, it } from 'vitest';
import { calificarIntento, validarArchivo, MIMES_PERMITIDOS } from '../src/lib/cuestionarios.js';

const preguntas = [
  {
    id: 'p1',
    opciones: [
      { id: 'a', esCorrecta: true },
      { id: 'b', esCorrecta: false },
    ],
  },
  {
    id: 'p2',
    opciones: [
      { id: 'c', esCorrecta: false },
      { id: 'd', esCorrecta: true },
    ],
  },
  {
    id: 'p3',
    opciones: [
      { id: 'e', esCorrecta: true },
      { id: 'f', esCorrecta: false },
    ],
  },
];

describe('autocalificación de cuestionarios (§6.4)', () => {
  it('calcula puntaje proporcional a las correctas', () => {
    expect(calificarIntento(preguntas, { p1: ['a'], p2: ['c'], p3: ['e'] }, 5).puntaje).toBe(3.33);
  });

  it('todas correctas dan la nota máxima', () => {
    expect(calificarIntento(preguntas, { p1: ['a'], p2: ['d'], p3: ['e'] }, 5)).toEqual({
      puntaje: 5,
      correctas: 3,
      total: 3,
    });
  });

  it('sin respuestas equivale a cero', () => {
    expect(calificarIntento(preguntas, {}, 5)).toEqual({ puntaje: 0, correctas: 0, total: 3 });
  });
});

describe('validación de archivos (§6.3)', () => {
  it('acepta un PDF dentro del límite', () => {
    expect(validarArchivo({ mime: 'application/pdf', tamano: 1024, maximoBytes: 52_428_800 })).toEqual({ valido: true });
  });

  it('rechaza tipos no permitidos', () => {
    expect(validarArchivo({ mime: 'application/x-msdownload', tamano: 10, maximoBytes: 100 }).valido).toBe(false);
  });

  it('rechaza archivos de más de 50 MB', () => {
    expect(validarArchivo({ mime: 'video/mp4', tamano: 60_000_000, maximoBytes: 52_428_800 }).valido).toBe(false);
  });

  it('la lista de MIME incluye los formatos de la muestra', () => {
    for (const mime of ['application/pdf', 'image/png', 'video/mp4', 'application/zip', 'text/plain']) {
      expect(MIMES_PERMITIDOS.has(mime)).toBe(true);
    }
  });
});
