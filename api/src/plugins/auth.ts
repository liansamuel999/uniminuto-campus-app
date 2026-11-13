import type { FastifyInstance, FastifyReply, FastifyRequest, preHandlerHookHandler } from 'fastify';
import { errores } from '../lib/errors.js';
import { esRol, type Rol } from '../lib/rbac.js';
import type { IdentidadToken, TokenVerifier } from '../modules/auth/verifier.js';

declare module 'fastify' {
  interface FastifyRequest {
    /** Identidad autenticada de la petición; `null` si la ruta no exige token. */
    actor: IdentidadToken | null;
  }
  interface FastifyInstance {
    /** `preHandler` que exige `Authorization: Bearer <ID Token>`. */
    autenticar: preHandlerHookHandler;
    /** `preHandler` que exige uno de los roles indicados (D-21). */
    requerirRoles: (...roles: Rol[]) => preHandlerHookHandler;
  }
}

/**
 * Registra la autenticación en la instancia de Fastify.
 * La autorización por rol es independiente del "rol activo" de la interfaz (§5).
 */
export function registrarPluginAuth(app: FastifyInstance, verificador: TokenVerifier): void {
  app.decorateRequest('actor', null);

  app.decorate('autenticar', async function (peticion: FastifyRequest, _respuesta: FastifyReply) {
    const cabecera = peticion.headers.authorization;
    if (!cabecera?.startsWith('Bearer ')) {
      throw errores.noAutorizado('Falta la cabecera Authorization: Bearer <token>');
    }
    const token = cabecera.slice('Bearer '.length).trim();
    if (token.length === 0) {
      throw errores.noAutorizado('El token enviado está vacío');
    }
    peticion.actor = await verificador.verificar(token);
  });

  app.decorate('requerirRoles', function (...roles: Rol[]) {
    const rolesValidos = roles.filter((rol) => esRol(rol));
    return async function (peticion: FastifyRequest) {
      const actor = peticion.actor;
      if (!actor) {
        throw errores.noAutorizado();
      }
      if (rolesValidos.length > 0 && !rolesValidos.some((rol) => actor.roles.includes(rol))) {
        throw errores.prohibido(`Se requiere uno de los roles: ${rolesValidos.join(', ')}`);
      }
    } as preHandlerHookHandler;
  });
}
