import { createHmac, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

interface Desafio {
  id: string;
  respuesta: number;
  token: string;
  expiraEn: number;
  usado: boolean;
}

const desafios = new Map<string, Desafio>();
const intentosPorIp = new Map<string, { ventana: number; cantidad: number }>();
const SECRETO = randomUUID();
const VIGENCIA_MS = 5 * 60_000;

function limpiar(): void {
  const ahora = Date.now();
  for (const [id, desafio] of desafios) {
    if (desafio.expiraEn < ahora) desafios.delete(id);
  }
  for (const [ip, intento] of intentosPorIp) {
    if (Date.now() - intento.ventana > 60_000) intentosPorIp.delete(ip);
  }
}

function permitir(ip: string): boolean {
  limpiar();
  const ahora = Date.now();
  const actual = intentosPorIp.get(ip);
  if (!actual || ahora - actual.ventana > 60_000) {
    intentosPorIp.set(ip, { ventana: ahora, cantidad: 1 });
    return true;
  }
  if (actual.cantidad >= 10) return false;
  actual.cantidad += 1;
  return true;
}

function firmar(id: string, respuesta: number): string {
  return createHmac('sha256', SECRETO).update(`${id}:${respuesta}`).digest('hex');
}

/**
 * Captcha aritmético propio de la muestra. No depende de servicios externos (útil para la demo
 * sin llaves de reCAPTCHA/Turnstile) y su respuesta se valida en el servidor.
 *
 * Limitación honesta: Firebase Authentication se invoca desde el cliente, por lo que un atacante
 * que conozca la API key pública podría saltarse esta pantalla. Por eso el captcha es una capa
 * adicional junto con contraseñas fuertes y el rate limit; no sustituye a Firebase App Check.
 */
export function registrarRutasCaptcha(app: FastifyInstance): void {
  app.post('/api/v1/auth/captcha', async (peticion, respuesta) => {
    const ip = peticion.ip || 'desconocida';
    if (!permitir(ip)) throw errores.conflicto('Demasiados intentos. Espera un minuto.');
    const a = randomInt(2, 20);
    const b = randomInt(2, 20);
    const id = randomUUID();
    const token = firmar(id, a + b);
    const desafio: Desafio = {
      id,
      respuesta: a + b,
      token,
      expiraEn: Date.now() + VIGENCIA_MS,
      usado: false,
    };
    desafios.set(id, desafio);
    return respuesta.code(201).send({
      id,
      pregunta: `¿Cuánto es ${a} + ${b}?`,
      token,
      expiraEn: new Date(desafio.expiraEn).toISOString(),
    });
  });

  app.post('/api/v1/auth/captcha/verificar', async (peticion) => {
    const { id, respuesta, token } = z
      .object({
        id: z.string().uuid(),
        respuesta: z.coerce.number().int(),
        token: z.string().length(64),
      })
      .parse(peticion.body ?? {});
    const desafio = desafios.get(id);
    if (!desafio || desafio.usado || desafio.expiraEn < Date.now()) {
      throw errores.datosInvalidos('El captcha venció. Solicita uno nuevo.');
    }
    const esperado = Buffer.from(firmar(id, desafio.respuesta), 'hex');
    const recibido = Buffer.from(token, 'hex');
    const firmaOk = esperado.length === recibido.length && timingSafeEqual(esperado, recibido);
    if (!firmaOk || respuesta !== desafio.respuesta) {
      throw errores.datosInvalidos('Respuesta incorrecta. Intenta de nuevo.');
    }
    desafio.usado = true;
    desafios.delete(id);
    return { valido: true };
  });
}
