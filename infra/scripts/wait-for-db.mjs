// Espera a que el puerto de CockroachDB acepte conexiones TCP.
// Uso: node infra/scripts/wait-for-db.mjs [timeoutMs]
import net from 'node:net';

const host = process.env.DATABASE_HOST ?? '127.0.0.1';
const port = Number(process.env.DATABASE_PORT ?? 26257);
const timeoutMs = Number(process.argv[2] ?? 60_000);
const inicio = Date.now();
const intervaloMs = 1_000;

function puertoAbierto() {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port });
    socket.setTimeout(2_000);
    socket.once('connect', () => {
      socket.destroy();
      resolve(true);
    });
    socket.once('timeout', () => {
      socket.destroy();
      resolve(false);
    });
    socket.once('error', () => resolve(false));
  });
}

for (;;) {
  if (await puertoAbierto()) {
    console.log(`Base de datos accesible en ${host}:${port}`);
    process.exit(0);
  }
  if (Date.now() - inicio > timeoutMs) {
    console.error(`No se pudo conectar a ${host}:${port} en ${timeoutMs} ms`);
    process.exit(1);
  }
  await new Promise((resolver) => setTimeout(resolver, intervaloMs));
}
