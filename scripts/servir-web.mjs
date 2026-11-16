#!/usr/bin/env node
/**
 * Sirve el build web de la demo (`app/build/web`) con respaldo SPA y CORS desactivado.
 *
 * Uso (después de `flutter build web --release --dart-define-from-file=env/dev.json`):
 *   node scripts/servir-web.mjs        # http://localhost:5173
 *   node scripts/servir-web.mjs 8080   # otro puerto
 *
 * Sirve index.html para las rutas del cliente (go_router) que no son archivos, para que
 * refrescar /aulas o /perfil no devuelva 404. No sustituye al servidor de producción: la demo
 * pública se despliega según docs/despliegue.md (§3 y §4).
 */
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';

const raiz = resolve(process.argv[3] ?? 'app/build/web');
const puerto = Number(process.argv[2] ?? 5173);

const tipos = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
};

if (!existsSync(join(raiz, 'index.html'))) {
  console.error(`No existe ${join(raiz, 'index.html')}.`);
  console.error('Compila primero: cd app && flutter build web --release --dart-define-from-file=env/dev.json');
  process.exit(1);
}

const servidor = createServer((peticion, respuesta) => {
  const url = new URL(peticion.url ?? '/', `http://localhost:${puerto}`);
  if (url.pathname === '/health') {
    respuesta.writeHead(200, { 'Content-Type': 'text/plain' });
    respuesta.end('ok');
    return;
  }

  let archivo = normalize(join(raiz, decodeURIComponent(url.pathname)));
  if (!archivo.startsWith(raiz)) {
    respuesta.writeHead(403);
    respuesta.end('Prohibido');
    return;
  }
  if (!existsSync(archivo) || statSync(archivo).isDirectory()) {
    archivo = join(raiz, 'index.html');
  }

  respuesta.writeHead(200, {
    'Content-Type': tipos[extname(archivo)] ?? 'application/octet-stream',
    'Cache-Control': extname(archivo) === '.html' ? 'no-cache' : 'public, max-age=3600',
  });
  createReadStream(archivo).pipe(respuesta);
});

servidor.listen(puerto, () => {
  console.log(`Demo web servida en http://localhost:${puerto} (raíz: ${raiz})`);
});
