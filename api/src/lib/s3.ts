import { HeadBucketCommand, S3Client } from '@aws-sdk/client-s3';
import type { Env } from '../config/env.js';

/**
 * Cliente S3 para MinIO (desarrollo) o Cloudflare R2 (demo). Un único código y
 * solo cambia la configuración (§3.1, §6.3).
 */
export function crearClienteS3(env: Env): S3Client | null {
  if (!env.S3_ENDPOINT || !env.S3_ACCESS_KEY || !env.S3_SECRET_KEY) {
    return null;
  }
  return new S3Client({
    endpoint: env.S3_ENDPOINT,
    region: env.S3_REGION,
    forcePathStyle: true,
    credentials: {
      accessKeyId: env.S3_ACCESS_KEY,
      secretAccessKey: env.S3_SECRET_KEY,
    },
  });
}

/** Comprueba que el bucket privado existe y es accesible (usado por `/health`). */
export async function verificarBucket(cliente: S3Client, bucket: string): Promise<boolean> {
  try {
    await cliente.send(new HeadBucketCommand({ Bucket: bucket }));
    return true;
  } catch {
    return false;
  }
}
