import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';

/// Diálogos de edición del aula para el docente (unidades, contenidos y actividades).
Future<bool> confirmarEliminacion(
  BuildContext context,
  String titulo,
  String mensaje,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(contexto).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(contexto).colorScheme.error,
            foregroundColor: Theme.of(contexto).colorScheme.onError,
          ),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return confirmado == true;
}

Future<bool?> editarAulaDialog(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> detalle,
) async {
  final nombre = TextEditingController(text: '${detalle['nombre'] ?? ''}');
  final descripcion = TextEditingController();
  final guardar = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Editar curso'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre del aula')),
            const SizedBox(height: 12),
            TextField(
              controller: descripcion,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(contexto).pop(true), child: const Text('Guardar')),
      ],
    ),
  );
  final textoNombre = nombre.text.trim();
  final textoDescripcion = descripcion.text.trim();
  nombre.dispose();
  descripcion.dispose();
  if (guardar != true) return false;
  try {
    await ref.read(repositorioAcademicoProvider).editarAula(
          '${detalle['id']}',
          nombre: textoNombre.isEmpty ? null : textoNombre,
          descripcion: textoDescripcion.isEmpty ? null : textoDescripcion,
        );
    return true;
  } on ApiException catch (error) {
    _aviso(context, error.mensaje);
    return false;
  }
}

Future<void> nuevaUnidadDialog(
  BuildContext context,
  WidgetRef ref,
  String aulaId,
  Future<void> Function() onRefresh,
) async {
  final titulo = TextEditingController();
  final crear = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Nueva unidad'),
      content: TextField(
        controller: titulo,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Título de la unidad'),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(contexto).pop(true), child: const Text('Crear')),
      ],
    ),
  );
  final textoTitulo = titulo.text.trim();
  titulo.dispose();
  if (crear != true || textoTitulo.length < 3) return;
  try {
    await ref.read(repositorioAcademicoProvider).crearUnidad(aulaId, titulo: textoTitulo);
    await onRefresh();
  } on ApiException catch (error) {
    _aviso(context, error.mensaje);
  }
}

Future<void> nuevoContenidoDialog(
  BuildContext context,
  WidgetRef ref,
  String unidadId,
  Future<void> Function() onRefresh,
) async {
  final datos = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => const _DialogoContenido(),
  );
  if (datos == null) return;
  try {
    await ref.read(repositorioAcademicoProvider).crearContenido(
          unidadId,
          tipo: '${datos['tipo']}',
          titulo: '${datos['titulo']}',
          descripcion: datos['descripcion'] as String?,
          objetoKey: datos['objetoKey'] as String?,
          urlExterna: datos['urlExterna'] as String?,
          mime: datos['mime'] as String?,
          tamano: datos['tamano'] as int?,
        );
    await onRefresh();
  } on ApiException catch (error) {
    _aviso(context, error.mensaje);
  }
}

Future<void> nuevaActividadDialog(
  BuildContext context,
  WidgetRef ref,
  String unidadId,
  Future<void> Function() onRefresh,
) async {
  final datos = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => const _DialogoActividad(),
  );
  if (datos == null) return;
  try {
    await ref.read(repositorioAcademicoProvider).crearActividad(
          unidadId,
          tipo: '${datos['tipo']}',
          titulo: '${datos['titulo']}',
          instrucciones: datos['instrucciones'] as String?,
          cierraEn: datos['cierraEn'] as DateTime?,
          corte: datos['corte'] as int,
          peso: datos['peso'] as double,
          formatosPermitidos: datos['formatosPermitidos'] as List<String>?,
        );
    await onRefresh();
  } on ApiException catch (error) {
    _aviso(context, error.mensaje);
  }
}

Future<void> editarActividadDialog(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> actividad,
  Future<void> Function() onRefresh,
) async {
  final cambiado = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoActividad(actual: actividad),
  );
  if (cambiado != true) return;
  await onRefresh();
}

class _DialogoContenido extends ConsumerStatefulWidget {
  const _DialogoContenido();

  @override
  ConsumerState<_DialogoContenido> createState() => _DialogoContenidoState();
}

class _DialogoContenidoState extends ConsumerState<_DialogoContenido> {
  final _titulo = TextEditingController();
  final _descripcion = TextEditingController();
  final _url = TextEditingController();
  String _tipo = 'ENLACE';
  String? _objetoKey;
  String? _mime;
  int? _tamano;
  bool _subiendo = false;
  String? _ayuda;

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _elegirArchivo() async {
    setState(() {
      _subiendo = true;
      _ayuda = null;
    });
    try {
      final archivo = await openFile();
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      final mime = archivo.mimeType ??
          (_tipo == 'PDF' ? 'application/pdf' : 'video/mp4');
      final firma = await ref.read(repositorioAcademicoProvider).subirArchivo(
            contexto: 'CONTENIDO',
            nombre: archivo.name,
            mime: mime,
            bytes: bytes,
          );
      setState(() {
        _objetoKey = '${firma['objetoKey']}';
        _mime = mime;
        _tamano = bytes.length;
        _ayuda = 'Archivo listo: ${archivo.name}';
      });
    } on ApiException catch (error) {
      setState(() => _ayuda = error.mensaje);
    } catch (_) {
      setState(() => _ayuda = 'No se pudo subir el archivo.');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  bool get _valido {
    if (_titulo.text.trim().length < 3) return false;
    if (_tipo == 'ENLACE') return Uri.tryParse(_url.text.trim())?.hasAbsolutePath == true;
    if (_tipo == 'ANUNCIO') return true;
    return _objetoKey != null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo contenido'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'PDF', child: Text('PDF')),
                DropdownMenuItem(value: 'VIDEO', child: Text('Video')),
                DropdownMenuItem(value: 'ENLACE', child: Text('Enlace')),
                DropdownMenuItem(value: 'ANUNCIO', child: Text('Anuncio')),
              ],
              onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titulo,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descripcion,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
            if (_tipo == 'ENLACE') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'URL (https://…)'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_tipo == 'PDF' || _tipo == 'VIDEO') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _subiendo ? null : _elegirArchivo,
                icon: _subiendo
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_objetoKey == null ? 'Elegir archivo' : 'Cambiar archivo'),
              ),
            ],
            if (_ayuda != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_ayuda!, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !_valido
              ? null
              : () => Navigator.of(context).pop({
                    'tipo': _tipo,
                    'titulo': _titulo.text.trim(),
                    'descripcion': _descripcion.text.trim(),
                    'objetoKey': _objetoKey,
                    'urlExterna': _tipo == 'ENLACE' ? _url.text.trim() : null,
                    'mime': _mime,
                    'tamano': _tamano,
                  }),
          child: const Text('Publicar'),
        ),
      ],
    );
  }
}

class _DialogoActividad extends ConsumerStatefulWidget {
  const _DialogoActividad({this.actual});

  final Map<String, dynamic>? actual;

  @override
  ConsumerState<_DialogoActividad> createState() => _DialogoActividadState();
}

class _DialogoActividadState extends ConsumerState<_DialogoActividad> {
  late final TextEditingController _titulo =
      TextEditingController(text: '${widget.actual?['titulo'] ?? ''}');
  late final TextEditingController _instrucciones =
      TextEditingController(text: '${widget.actual?['instrucciones'] ?? ''}');
  late final TextEditingController _peso = TextEditingController(
    text: '${(widget.actual?['peso'] as num?)?.toStringAsFixed(0) ?? 20}',
  );
  late final TextEditingController _formatos = TextEditingController(
    text: ((widget.actual?['formatosPermitidos'] as List<dynamic>?) ?? const []).join(', '),
  );
  late String _tipo = '${widget.actual?['tipo'] ?? 'TAREA'}';
  int _corte = 1;
  DateTime? _cierraEn;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _corte = (widget.actual?['corte'] as num?)?.toInt() ?? 1;
    _cierraEn = DateTime.tryParse('${widget.actual?['cierraEn']}');
  }

  @override
  void dispose() {
    _titulo.dispose();
    _instrucciones.dispose();
    _peso.dispose();
    _formatos.dispose();
    super.dispose();
  }

  List<String> get _listaFormatos => _formatos.text
      .split(',')
      .map((formato) => formato.trim().toLowerCase().replaceAll('.', ''))
      .where((formato) => formato.isNotEmpty)
      .toList();

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _cierraEn ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha == null) return;
    if (!mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_cierraEn ?? DateTime.now()),
    );
    setState(() {
      _cierraEn = DateTime(fecha.year, fecha.month, fecha.day, hora?.hour ?? 23, hora?.minute ?? 59);
    });
  }

  Future<void> _guardar() async {
    final peso = double.tryParse(_peso.text.trim().replaceAll(',', '.'));
    if (_titulo.text.trim().length < 3 || peso == null || peso <= 0 || peso > 100) return;
    setState(() => _guardando = true);
    try {
      if (widget.actual == null) {
        Navigator.of(context).pop({
          'tipo': _tipo,
          'titulo': _titulo.text.trim(),
          'instrucciones': _instrucciones.text.trim(),
          'cierraEn': _cierraEn,
          'corte': _corte,
          'peso': peso,
          'formatosPermitidos': _tipo == 'TAREA' ? _listaFormatos : null,
        });
      } else {
        await ref.read(repositorioAcademicoProvider).editarActividad(
              '${widget.actual!['id']}',
              titulo: _titulo.text.trim(),
              instrucciones: _instrucciones.text.trim(),
              cierraEn: _cierraEn,
              peso: peso,
              formatosPermitidos: _tipo == 'TAREA' ? _listaFormatos : null,
            );
        if (mounted) Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.actual != null;
    return AlertDialog(
      title: Text(esEdicion ? 'Editar actividad' : 'Nueva actividad'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!esEdicion)
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'TAREA', child: Text('Tarea')),
                  DropdownMenuItem(value: 'CUESTIONARIO', child: Text('Cuestionario')),
                  DropdownMenuItem(value: 'FORO', child: Text('Foro')),
                ],
                onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
              ),
            const SizedBox(height: 8),
            TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Título')),
            const SizedBox(height: 8),
            TextField(
              controller: _instrucciones,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Instrucciones / descripción'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _corte,
                    decoration: const InputDecoration(labelText: 'Corte'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Corte 1')),
                      DropdownMenuItem(value: 2, child: Text('Corte 2')),
                      DropdownMenuItem(value: 3, child: Text('Corte 3')),
                    ],
                    onChanged: esEdicion ? null : (valor) => setState(() => _corte = valor ?? _corte),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _peso,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Peso (%)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _elegirFecha,
              icon: const Icon(Icons.event),
              label: Text(
                _cierraEn == null ? 'Fecha de cierre' : 'Cierra ${fechaHoraCorta(_cierraEn)}',
              ),
            ),
            if (_tipo == 'TAREA') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _formatos,
                decoration: const InputDecoration(
                  labelText: 'Formatos permitidos (opcional)',
                  hintText: 'pdf, png, docx',
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Sepáralos con coma; vacío = cualquier formato de la muestra.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
            if (_tipo == 'CUESTIONARIO' && !esEdicion)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'El cuestionario se crea con 3 preguntas de ejemplo para la demostración.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(esEdicion ? 'Guardar cambios' : 'Crear'),
        ),
      ],
    );
  }
}

void _aviso(BuildContext context, String mensaje) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}
