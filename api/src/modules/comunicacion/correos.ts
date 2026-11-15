import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';

import { errores } from '../../lib/errors.js';

export interface CorreoSimulado {
  id: string;
  asunto: string;
  cuerpo: string;
  creadoEn: string;
}

export interface RepositorioCorreos {
  replicar(
    uidDocente: string,
    anuncioId: string,
    aulaId: string,
    asunto: string,
    cuerpo: string,
  ): Promise<number>;
  listar(uidFirebase: string): Promise<CorreoSimulado[]>;
}

export function crearRepositorioCorreos(pool: Pool): RepositorioCorreos {
  return {
    async replicar(uidDocente, anuncioId, aulaId, asunto, cuerpo) {
      const acceso = await pool.query<{ id: string }>(
        `SELECT a.id FROM aula a
         JOIN grupo g ON g.id = a.grupo_id
         JOIN usuario u ON u.id = g.docente_id
         WHERE a.id = $1 AND u.uid_firebase = $2`,
        [aulaId, uidDocente],
      );
      if (!acceso.rows[0]) throw errores.prohibido('Solo el docente del aula puede replicar el anuncio');

      const resultado = await pool.query(
        `INSERT INTO correo_simulado (anuncio_id, destinatario, asunto, cuerpo)
         SELECT $1, i.estudiante_id, $2, $3
         FROM inscripcion i JOIN aula a ON a.grupo_id = i.grupo_id
         WHERE a.id = $4 AND i.estado = 'ACTIVA'
         ON CONFLICT (anuncio_id, destinatario) DO NOTHING`,
        [anuncioId, asunto, cuerpo, aulaId],
      );
      return resultado.rowCount ?? 0;
    },

    async listar(uidFirebase) {
      const resultado = await pool.query<{
        id: string;
        asunto: string;
        cuerpo: string;
        creado_en: string | Date;
      }>(
        `SELECT c.id, c.asunto, c.cuerpo, c.creado_en
         FROM correo_simulado c JOIN usuario u ON u.id = c.destinatario
         WHERE u.uid_firebase = $1 ORDER BY c.creado_en DESC LIMIT 100`,
        [uidFirebase],
      );
      return resultado.rows.map((fila) => ({
        id: fila.id,
        asunto: fila.asunto,
        cuerpo: fila.cuerpo,
        creadoEn: (fila.creado_en instanceof Date ? fila.creado_en : new Date(fila.creado_en)).toISOString(),
      }));
    },
  };
}

const esquemaReplica = z
  .object({
    aulaId: z.string().uuid(),
    asunto: z.string().trim().min(2).max(160),
    cuerpo: z.string().trim().min(2).max(4000),
  })
  .strict();

export function registrarRutasCorreos(app: FastifyInstance, repo: RepositorioCorreos): void {
  app.post('/api/v1/anuncios/:id/replicar-correo', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().min(1).max(120) }).parse(peticion.params);
    const datos = esquemaReplica.parse(peticion.body ?? {});
    const creados = await repo.replicar(peticion.actor!.uid, id, datos.aulaId, datos.asunto, datos.cuerpo);
    return { anuncioId: id, creados };
  });

  app.get('/api/v1/correos-simulados', { preHandler: app.autenticar }, async (peticion) =>
    repo.listar(peticion.actor!.uid),
  );
}
