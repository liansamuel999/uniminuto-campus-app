import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import type { S3Client } from '@aws-sdk/client-s3';
import { z } from 'zod';

import type { Env } from '../../config/env.js';
import { errores } from '../../lib/errors.js';
import { validarArchivo } from '../../lib/cuestionarios.js';
import { urlLectura, urlSubida } from '../../lib/s3_archivos.js';

export interface ArchivoMetadatos {
  id: string;
  objetoKey: string;
  mime: string;
  tamano: number;
  subidoPor: string | null;
}

export interface RepositorioArchivos {
  crear(datos: Omit<ArchivoMetadatos, 'id'>): Promise<ArchivoMetadatos>;
  obtener(id: string): Promise<ArchivoMetadatos | null>;
}

const PREFIJOS: Record<string, string> = {
  ENTREGA: 'entregas',
  CONTENIDO: 'aulas',
  FORO: 'foros',
  PERFIL: 'perfiles',
};

export function crearRepositorioArchivos(pool: Pool): RepositorioArchivos {
  return {
    async crear(datos) {
      const resultado = await pool.query<{ id: string }>(
        `INSERT INTO archivo (objeto_key, mime, tamano, subido_por) VALUES ($1, $2, $3, $4) RETURNING id`,
        [datos.objetoKey, datos.mime, datos.tamano, datos.subidoPor],
      );
      return { id: resultado.rows[0]!.id, ...datos };
    },
    async obtener(id) {
      const resultado = await pool.query<{
        id: string;
        objeto_key: string;
        mime: string;
        tamano: string;
        subido_por: string | null;
      }>('SELECT id, objeto_key, mime, tamano, subido_por FROM archivo WHERE id = $1', [id]);
      const fila = resultado.rows[0];
      if (!fila) return null;
      return {
        id: fila.id,
        objetoKey: fila.objeto_key,
        mime: fila.mime,
        tamano: Number(fila.tamano),
        subidoPor: fila.subido_por,
      };
    },
  };
}

const esquemaSubida = z
  .object({
    contexto: z.enum(['ENTREGA', 'CONTENIDO', 'FORO', 'PERFIL']),
    nombre: z.string().trim().min(1).max(120),
    mime: z.string().trim().min(3).max(120),
    tamano: z.number().int().positive(),
  })
  .strict();

export function registrarRutasArchivos(
  app: FastifyInstance,
  repo: RepositorioArchivos,
  s3: S3Client,
  env: Env,
): void {
  app.post('/api/v1/archivos/subida', { preHandler: app.autenticar }, async (peticion, respuesta) => {
    const datos = esquemaSubida.parse(peticion.body ?? {});
    const validacion = validarArchivo({
      mime: datos.mime,
      tamano: datos.tamano,
      maximoBytes: env.UPLOAD_MAX_BYTES,
    });
    if (!validacion.valido) throw errores.datosInvalidos(validacion.motivo ?? 'Archivo inválido');

    const nombreSeguro = datos.nombre.replace(/[^\w.\-]/g, '_');
    const prefijo = PREFIJOS[datos.contexto] ?? 'otros';
    const objetoKey =
      datos.contexto === 'PERFIL'
        ? `perfiles/${peticion.actor!.uid}.${nombreSeguro.split('.').pop() ?? 'jpg'}`
        : `${prefijo}/${peticion.actor!.uid}/${randomUUID()}-${nombreSeguro}`;

    const archivo = await repo.crear({
      objetoKey,
      mime: datos.mime,
      tamano: datos.tamano,
      subidoPor: null,
    });
    const urlPut = await urlSubida(s3, env.S3_BUCKET, objetoKey, datos.mime);

    return respuesta.code(201).send({
      archivoId: archivo.id,
      objetoKey,
      urlPut,
      expiraEn: new Date(Date.now() + 10 * 60_000).toISOString(),
    });
  });

  app.get('/api/v1/archivos/:id/url', { preHandler: app.autenticar }, async (peticion) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(peticion.params);
    const archivo = await repo.obtener(id);
    if (!archivo) throw errores.noEncontrado('El archivo no existe');
    const url = await urlLectura(s3, env.S3_BUCKET, archivo.objetoKey);
    return {
      url,
      mime: archivo.mime,
      tamano: archivo.tamano,
      expiraEn: new Date(Date.now() + 15 * 60_000).toISOString(),
    };
  });
}
