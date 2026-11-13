import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import type { JwkEc } from '../../config/institution_keys.js';
import { errores } from '../../lib/errors.js';
import { esquemaVinculacion, type RepositorioCarnet } from './carnet.js';

const esquemaParametro = z.object({ id: z.string().uuid('El id del dispositivo no es válido') });

/** Rutas de carnet y dispositivos (§6.1, §7.7). */
export function registrarRutasCarnet(app: FastifyInstance, repositorio: RepositorioCarnet): void {
  app.get('/api/v1/carnet/mio', { preHandler: app.autenticar }, async (peticion) => {
    const resumen = await repositorio.obtenerResumen(peticion.actor!.uid);
    if (!resumen) {
      throw errores.noEncontrado('El usuario autenticado no tiene carnet registrado');
    }
    return resumen;
  });

  app.post('/api/v1/dispositivos', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const datos = esquemaVinculacion.parse(peticion.body ?? {});
    const resumen = await repositorio.vincular(peticion.actor!.uid, {
      nombreDispositivo: datos.nombreDispositivo,
      clavePublicaJwk: datos.clavePublicaJwk as unknown as JwkEc,
    });
    return respuesta.code(201).send(resumen);
  });

  app.post(
    '/api/v1/dispositivos/renovar-certificado',
    { preHandler: app.autenticar },
    async (peticion) => repositorio.renovar(peticion.actor!.uid),
  );

  app.delete('/api/v1/dispositivos/:id', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = esquemaParametro.parse(peticion.params);
    const puedeRevocarAjeno = peticion.actor?.roles.includes('SOPORTE') ?? false;
    await repositorio.revocar(peticion.actor!.uid, id, puedeRevocarAjeno);
    return { ok: true, dispositivoId: id };
  });
}
