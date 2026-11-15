import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';

/// Abre un contenido del aula según su tipo: enlace, PDF, video o anuncio.
///
/// Los binarios se leen con URL prefirmada de 15 minutos (§6.3); si el objeto de demostración
/// aún no está en el datalake se informa al usuario en lugar de dejar el toque sin respuesta.
Future<void> abrirContenido(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> contenido, {
  bool esDocente = false,
}) async {
  final tipo = '${contenido['tipo']}';
  final titulo = '${contenido['titulo']}';
  final descripcion = contenido['descripcion'] as String?;

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

  if (tipo == 'ENLACE') {
    final url = contenido['urlExterna'] as String?;
    if (url == null || url.isEmpty) {
      _aviso(context, 'Este enlace no tiene URL configurada.');
      return;
    }
    await abrirEnlace(context, url);
    return;
  }

  final urlExterna = contenido['urlExterna'] as String?;
  if (urlExterna != null && urlExterna.isNotEmpty) {
    await abrirEnlace(context, urlExterna);
    return;
  }

  final objetoKey = contenido['objetoKey'] as String?;
  if (objetoKey == null || objetoKey.isEmpty) {
    _aviso(context, 'Este contenido todavía no tiene un archivo adjunto.');
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text('Preparando ${tipo == 'PDF' ? 'el documento' : 'el video'}…')),
  );
  try {
    final url = await ref.read(repositorioAcademicoProvider).urlDeObjeto(objetoKey);
    if (!context.mounted) return;
    await abrirEnlace(context, url);
  } on ApiException catch (error) {
    _aviso(context, error.mensaje);
  } catch (_) {
    _aviso(context, 'No se pudo obtener el archivo. ¿Está el datalake disponible?');
  }
}

void _aviso(BuildContext context, String mensaje) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}
