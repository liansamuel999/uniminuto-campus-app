import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';

/// Abre un contenido del aula según su tipo: enlace, archivo (PDF, imagen, video, Office) o anuncio.
///
/// Los binarios se leen con URL prefirmada de 15 minutos (§6.3); la API verifica que el objeto
/// exista y, si el datalake se reinició, la app muestra un mensaje claro en lugar de la página XML
/// de MinIO con `NoSuchKey` (corrección de la muestra).
Future<void> abrirContenido(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> contenido, {
  bool esDocente = false,
}) async {
  final tipo = '${contenido['tipo']}';
  final titulo = '${contenido['titulo']}';
  final descripcion = contenido['descripcion'] as String?;
  final mime = '${contenido['mime'] ?? ''}';

  if (tipo == 'ANUNCIO') {
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(titulo),
        content: Text(
          (descripcion == null || descripcion.trim().isEmpty)
              ? 'Anuncio del aula sin descripción adicional.'
              : descripcion,
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Entendido')),
        ],
      ),
    );
    return;
  }

  final urlExterna = contenido['urlExterna'] as String?;
  if (tipo == 'ENLACE' || (urlExterna != null && urlExterna.isNotEmpty)) {
    if (urlExterna == null || urlExterna.isEmpty) {
      _aviso(context, 'Este enlace no tiene URL configurada.');
      return;
    }
    await abrirEnlace(context, urlExterna);
    return;
  }

  final objetoKey = contenido['objetoKey'] as String?;
  if (objetoKey == null || objetoKey.isEmpty) {
    _aviso(context, 'Este contenido todavía no tiene un archivo adjunto.');
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparando el archivo…')));
  try {
    final url = await ref.read(repositorioAcademicoProvider).urlDeObjeto(objetoKey);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();

    // Las imágenes se previsualizan dentro de la app; el resto se abre con la aplicación del
    // sistema (visor de PDF, Office, reproductor de video o navegador).
    if (mime.startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (contexto) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(titulo, overflow: TextOverflow.ellipsis),
                automaticallyImplyLeading: false,
                actions: [IconButton(onPressed: () => Navigator.of(contexto).pop(), icon: const Icon(Icons.close))],
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No se pudo cargar la imagen.'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    await abrirEnlace(context, url);
  } on ApiException catch (error) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(error.mensaje)));
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo. Inténtalo de nuevo.')),
      );
    }
  }
}

void _aviso(BuildContext context, String mensaje) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}
