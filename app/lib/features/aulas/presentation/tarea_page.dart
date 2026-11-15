import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import '../data/cola_entregas.dart';

/// Formulario de entrega de una tarea, con cola local si no hay conexión (§6.2).
///
/// - Muestra primero las instrucciones completas y luego el formulario.
/// - El texto es opcional si se adjunta un archivo.
/// - Respeta los formatos permitidos por el docente, si los definió.
class TareaPage extends ConsumerStatefulWidget {
  const TareaPage({super.key, required this.actividad});

  final Map<String, dynamic> actividad;

  @override
  ConsumerState<TareaPage> createState() => _TareaPageState();
}

class _TareaPageState extends ConsumerState<TareaPage> {
  final _texto = TextEditingController();
  final List<Map<String, dynamic>> _adjuntos = [];
  bool _adjuntando = false;
  bool _enviando = false;
  bool _cargandoEstado = true;
  String? _mensaje;
  Map<String, dynamic>? _entregaPrevia;

  String get _actividadId => '${widget.actividad['id']}';
  List<String> get _formatos => (widget.actividad['formatosPermitidos'] as List<dynamic>? ?? const [])
      .map((formato) => '$formato')
      .toList();

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _cargarEstado() async {
    setState(() => _cargandoEstado = true);
    try {
      final entrega = await ref.read(repositorioAcademicoProvider).miEntrega(_actividadId);
      if (mounted) setState(() => _entregaPrevia = entrega);
    } catch (_) {
      // Sin conexión: se permite preparar la entrega y encolarla.
    } finally {
      if (mounted) setState(() => _cargandoEstado = false);
    }
  }

  String _extension(String nombre) {
    final partes = nombre.toLowerCase().split('.');
    return partes.length > 1 ? partes.last : '';
  }

  Future<void> _adjuntar() async {
    setState(() {
      _adjuntando = true;
      _mensaje = null;
    });
    try {
      final archivo = await openFile();
      if (archivo == null) return;
      final extension = _extension(archivo.name);
      if (_formatos.isNotEmpty && !_formatos.contains(extension)) {
        setState(() => _mensaje = 'Este docente solo acepta: ${_formatos.join(', ')}.');
        return;
      }
      final bytes = await archivo.readAsBytes();
      final mime = archivo.mimeType ?? 'application/octet-stream';
      final firma = await ref.read(repositorioAcademicoProvider).subirArchivo(
            contexto: 'ENTREGA',
            nombre: archivo.name,
            mime: mime,
            bytes: bytes,
          );
      if (!mounted) return;
      setState(() {
        _adjuntos.add({
          'objetoKey': firma['objetoKey'],
          'nombre': archivo.name,
          'mime': mime,
          'tamano': bytes.length,
        });
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _mensaje = 'No se pudo adjuntar: ${error.mensaje}');
    } catch (_) {
      if (mounted) {
        setState(() => _mensaje = 'No se pudo adjuntar el archivo. Revisa la conexión.');
      }
    } finally {
      if (mounted) setState(() => _adjuntando = false);
    }
  }

  Future<void> _enviar({required bool soloGuardar}) async {
    final texto = _texto.text.trim();
    if (texto.length < 5 && _adjuntos.isEmpty) {
      setState(() => _mensaje = 'Escribe una respuesta o adjunta un archivo.');
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = null;
    });

    final entregaId = nuevoUuid();
    final creada = DateTime.now();
    final cola = ref.read(colaEntregasProvider);

    if (soloGuardar) {
      try {
        await cola.encolar(
          entregaId: entregaId,
          actividadId: _actividadId,
          texto: texto,
          creadaEnCliente: creada,
          adjuntos: _adjuntos,
        );
        if (mounted) setState(() => _mensaje = 'Guardada en el dispositivo. Se enviará al reconectar.');
      } catch (_) {
        if (mounted) setState(() => _mensaje = 'No se pudo guardar la entrega en el dispositivo.');
      } finally {
        if (mounted) setState(() => _enviando = false);
      }
      return;
    }

    try {
      final respuesta = await ref.read(apiClientProvider).postJson('/entregas', cuerpo: {
        'entregaId': entregaId,
        'actividadId': _actividadId,
        'texto': texto,
        'creadaEnCliente': creada.toUtc().toIso8601String(),
        'adjuntos': _adjuntos,
      });
      if (!mounted) return;
      setState(() => _mensaje = 'Entrega registrada como ${respuesta['estado']}.');
      _texto.clear();
      setState(() => _adjuntos.clear());
      await _cargarEstado();
    } on ApiException catch (error) {
      if (error.esSinRed) {
        await cola.encolar(
          entregaId: entregaId,
          actividadId: _actividadId,
          texto: texto,
          creadaEnCliente: creada,
          adjuntos: _adjuntos,
        );
        if (mounted) setState(() => _mensaje = 'Sin conexión: quedó guardada y se enviará sola.');
      } else if (error.codigo == 'CONFLICTO') {
        if (mounted) setState(() => _mensaje = 'Ya registraste una entrega para esta actividad.');
        await _cargarEstado();
      } else {
        if (mounted) setState(() => _mensaje = error.mensaje);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _sincronizar() async {
    final enviadas = await ref.read(colaEntregasProvider).sincronizar();
    if (!mounted) return;
    setState(() => _mensaje = enviadas == 0
        ? 'No había entregas pendientes o sigue sin conexión.'
        : 'Se enviaron $enviadas entrega(s) pendiente(s).');
    if (enviadas > 0) await _cargarEstado();
  }

  @override
  Widget build(BuildContext context) {
    final actividad = widget.actividad;
    final pendientes = ref.read(colaEntregasProvider).pendientes().length;
    final cierra = DateTime.tryParse('${actividad['cierraEn']}');
    final colores = Theme.of(context).colorScheme;
    final yaEntregada = _entregaPrevia != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${actividad['titulo']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (pendientes > 0)
            Tooltip(
              message: 'Sincronizar entregas pendientes',
              child: IconButton(onPressed: _sincronizar, icon: const Icon(Icons.cloud_upload_outlined)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text('Tarea'), visualDensity: VisualDensity.compact),
                      const SizedBox(width: 8),
                      Text('${actividad['peso']}% del corte ${actividad['corte']}'),
                      const Spacer(),
                      if (cierra != null)
                        Text('Vence en ${tiempoRestante(cierra)}', style: TextStyle(color: colores.primary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ('${actividad['instrucciones'] ?? ''}').trim().isEmpty
                        ? 'El docente no agregó instrucciones.'
                        : '${actividad['instrucciones']}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (cierra != null) ...[
                    const SizedBox(height: 8),
                    Text('Fecha límite: ${fechaHoraCorta(cierra)}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (_formatos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.attach_file, size: 16, color: colores.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Formatos aceptados: ${_formatos.join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (pendientes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Tienes $pendientes entrega(s) guardada(s) sin enviar.',
                        style: TextStyle(color: colores.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_cargandoEstado)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          if (yaEntregada) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colores.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline),
                      const SizedBox(width: 8),
                      Text(
                        'Entrega registrada (${_entregaPrevia?['estado']})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Enviada: ${fechaHoraCorta(DateTime.tryParse('${_entregaPrevia?['recibidaEnServidor']}'))}'),
                  if (_entregaPrevia?['nota'] != null)
                    Text('Nota: ${_entregaPrevia?['nota']}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Text('Tu respuesta', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            TextField(
              controller: _texto,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Escribe aquí… (opcional si adjuntas un archivo)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _adjuntando ? null : _adjuntar,
              icon: _adjuntando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.attach_file),
              label: Text(_adjuntando ? 'Subiendo…' : 'Adjuntar archivo'),
            ),
            if (_adjuntos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final adjunto in _adjuntos)
                    Chip(
                      avatar: const Icon(Icons.insert_drive_file, size: 16),
                      label: Text('${adjunto['nombre']}'),
                      onDeleted: () => setState(() => _adjuntos.remove(adjunto)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            if (_mensaje != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_mensaje!, style: TextStyle(color: colores.onSurfaceVariant)),
              ),
            FilledButton.icon(
              onPressed: _enviando ? null : () => _enviar(soloGuardar: false),
              icon: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: const Text('Enviar entrega'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _enviando ? null : () => _enviar(soloGuardar: true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar para enviar después'),
            ),
          ],
          if (_mensaje != null && yaEntregada) ...[
            const SizedBox(height: 8),
            Text(_mensaje!),
          ],
        ],
      ),
    );
  }
}
