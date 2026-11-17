import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Editor de contenido del aula en página completa (no ventana emergente).
///
/// Admite **archivos en general** (PDF, imágenes, video, Word, PowerPoint, Excel, etc.), enlaces y
/// anuncios. El tipo interno se deduce del MIME/extensión para que el estudiante vea el icono y el
/// visor adecuados (corrección de la muestra).
class ContenidoEditorPage extends ConsumerStatefulWidget {
  const ContenidoEditorPage({
    super.key,
    required this.unidadId,
    this.contenidoActual,
  });

  final String unidadId;
  final Map<String, dynamic>? contenidoActual;

  @override
  ConsumerState<ContenidoEditorPage> createState() => _ContenidoEditorPageState();
}

enum _ModoContenido { archivo, enlace, anuncio }

class _ContenidoEditorPageState extends ConsumerState<ContenidoEditorPage> {
  late final TextEditingController _titulo;
  late final TextEditingController _descripcion;
  late final TextEditingController _url;

  late _ModoContenido _modo;
  String? _objetoKey;
  String? _archivoNombre;
  String? _archivoMime;
  int? _tamano;
  bool _subiendo = false;
  bool _guardando = false;
  String? _error;

  static const int maximoBytes = 50 * 1024 * 1024;

  bool get _editando => widget.contenidoActual != null;

  @override
  void initState() {
    super.initState();
    final actual = widget.contenidoActual;
    _titulo = TextEditingController(text: '${actual?['titulo'] ?? ''}');
    _descripcion = TextEditingController(text: '${actual?['descripcion'] ?? ''}');
    _url = TextEditingController(text: '${actual?['urlExterna'] ?? ''}');
    _objetoKey = actual?['objetoKey'] as String?;
    _archivoNombre = _objetoKey?.split('/').last;
    _archivoMime = actual?['mime'] as String?;
    _tamano = (actual?['tamano'] as num?)?.toInt();
    final tipo = '${actual?['tipo'] ?? 'ARCHIVO'}';
    _modo = tipo == 'ANUNCIO'
        ? _ModoContenido.anuncio
        : (tipo == 'ENLACE' ? _ModoContenido.enlace : _ModoContenido.archivo);
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _url.dispose();
    super.dispose();
  }

  String _extension(String nombre) {
    final partes = nombre.toLowerCase().split('.');
    return partes.length > 1 ? partes.last : '';
  }

  /// Traduce el archivo elegido al tipo de contenido que entiende la app.
  String _tipoDesdeArchivo(String nombre, String mime) {
    final extension = _extension(nombre);
    if (mime == 'application/pdf' || extension == 'pdf') return 'PDF';
    if (mime.startsWith('image/') || ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp'].contains(extension)) {
      return 'IMAGEN';
    }
    if (mime.startsWith('video/') || ['mp4', 'webm', 'mov', 'avi', 'mkv'].contains(extension)) {
      return 'VIDEO';
    }
    if (['ppt', 'pptx', 'odp', 'key'].contains(extension)) return 'PRESENTACION';
    if (['xls', 'xlsx', 'ods', 'csv'].contains(extension)) return 'HOJA_CALCULO';
    if (['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'pkt', 'pka', 'pcap', 'pcapng'].contains(extension)) {
      return 'ARCHIVO';
    }
    return 'DOCUMENTO';
  }

  Future<void> _elegirArchivo() async {
    setState(() => _error = null);
    try {
      final archivo = await openFile();
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (bytes.length > maximoBytes) {
        setState(() => _error = 'El archivo supera el máximo de 50 MB.');
        return;
      }
      if (mounted) {
        setState(() {
          _archivoNombre = archivo.name;
          _archivoMime = archivo.mimeType ?? 'application/octet-stream';
          _tamano = bytes.length;
          _objetoKey = null;
          _archivoBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo leer el archivo seleccionado.');
    }
  }

  List<int>? _archivoBytes;

  Future<void> _guardar() async {
    final titulo = _titulo.text.trim();
    if (titulo.length < 3) {
      setState(() => _error = 'Escribe un título de al menos 3 caracteres.');
      return;
    }
    if (_modo == _ModoContenido.enlace) {
      final url = _url.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        setState(() => _error = 'El enlace debe empezar por http:// o https://');
        return;
      }
    }
    if (_modo == _ModoContenido.archivo && _objetoKey == null && _archivoBytes == null) {
      setState(() => _error = 'Selecciona un archivo para subir.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositorioAcademicoProvider);
      var objetoKey = _objetoKey;
      var mime = _archivoMime;
      var tamano = _tamano;
      var tipo = 'ARCHIVO';
      String? urlExterna;

      switch (_modo) {
        case _ModoContenido.archivo:
          if (_archivoBytes != null) {
            setState(() => _subiendo = true);
            final firma = await repo.subirArchivo(
              contexto: 'CONTENIDO',
              nombre: _archivoNombre!,
              mime: mime!,
              bytes: Uint8List.fromList(_archivoBytes!),
            );
            objetoKey = '${firma['objetoKey']}';
            tamano = _archivoBytes!.length;
            setState(() => _subiendo = false);
          }
          tipo = _tipoDesdeArchivo(_archivoNombre ?? 'archivo', mime ?? '');
          urlExterna = null;
        case _ModoContenido.enlace:
          tipo = 'ENLACE';
          urlExterna = _url.text.trim();
          objetoKey = null;
          mime = null;
          tamano = null;
        case _ModoContenido.anuncio:
          tipo = 'ANUNCIO';
          urlExterna = null;
          objetoKey = null;
          mime = null;
          tamano = null;
      }

      if (_editando) {
        await repo.editarContenido(
          '${widget.contenidoActual!['id']}',
          titulo: titulo,
          descripcion: _descripcion.text.trim(),
          tipo: tipo,
          objetoKey: objetoKey,
          urlExterna: urlExterna,
          mime: mime,
          tamano: tamano,
        );
      } else {
        await repo.crearContenido(
          widget.unidadId,
          tipo: tipo,
          titulo: titulo,
          descripcion: _descripcion.text.trim(),
          objetoKey: objetoKey,
          urlExterna: urlExterna,
          mime: mime,
          tamano: tamano,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar el contenido.');
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
          _subiendo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar contenido' : 'Nuevo contenido'),
        actions: [
          TextButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(_guardando ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_ModoContenido>(
            segments: const [
              ButtonSegment(value: _ModoContenido.archivo, icon: Icon(Icons.attach_file), label: Text('Archivo')),
              ButtonSegment(value: _ModoContenido.enlace, icon: Icon(Icons.link), label: Text('Enlace')),
              ButtonSegment(value: _ModoContenido.anuncio, icon: Icon(Icons.campaign_outlined), label: Text('Anuncio')),
            ],
            selected: {_modo},
            onSelectionChanged: (seleccion) => setState(() => _modo = seleccion.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titulo,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descripcion,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: _modo == _ModoContenido.anuncio ? 'Mensaje del anuncio' : 'Descripción (opcional)',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_modo == _ModoContenido.archivo) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.upload_file, color: colores.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _archivoNombre ?? 'Ningún archivo seleccionado',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'PDF, imágenes, video, Word, PowerPoint, Excel… hasta 50 MB',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _guardando ? null : _elegirArchivo,
                      child: Text(_objetoKey != null || _archivoNombre != null ? 'Cambiar' : 'Elegir'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_modo == _ModoContenido.enlace) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL del enlace',
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_subiendo) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text('Subiendo el archivo al datalake…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colores.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: colores.onErrorContainer)),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save_outlined),
            label: Text(_guardando ? 'Guardando…' : 'Guardar contenido'),
          ),
        ],
      ),
    );
  }
}
