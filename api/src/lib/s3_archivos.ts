import { GetObjectCommand, PutObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const SEGUNDOS_SUBIDA = 10 * 60;
const SEGUNDOS_LECTURA = 15 * 60;

/** URL prefirmada de subida (10 minutos, §6.3). */
export function urlSubida(
  cliente: S3Client,
  bucket: string,
  clave: string,
  mime: string,
): Promise<string> {
  return getSignedUrl(
    cliente,
    new PutObjectCommand({ Bucket: bucket, Key: clave, ContentType: mime }),
    { expiresIn: SEGUNDOS_SUBIDA },
  );
}

/** URL prefirmada de lectura (15 minutos, §6.3). */
export function urlLectura(cliente: S3Client, bucket: string, clave: string): Promise<string> {
  return getSignedUrl(cliente, new GetObjectCommand({ Bucket: bucket, Key: clave }), {
    expiresIn: SEGUNDOS_LECTURA,
  });
}
