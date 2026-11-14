import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../data/cola_entregas.dart';

/// Formulario de entrega de una tarea, con cola local si no hay conexión (§6.2).
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
  String? _mensaje;

  Future<void> _adjuntar() async {
    setState(() {
      _adjuntando = true;
      _mensaje = null;
    });
    try {
      final archivo = await openFile();
      final bytes = archivo == null ? null : await archivo.readAsBytes();
      if (archivo == null || bytes == null) return;

      final api = ref.read(apiClientProvider);
      final firma = await api.postJson('/archivos/subida', cuerpo: {
        'contexto': 'ENTREGA',
        'nombre': archivo.name,
        'mime': archivo.mimeType ?? 'application/octet-stream',
        'tamano': bytes.length,
      });

      // El binario va directo al datalake con la URL prefirmada, sin pasar por la API.
      await api.dio.put<dynamic>(
        '${firma['urlPut']}',
        data: bytes,
        options: Options(headers: {'Content-Type': 'application/octet-stream'}),
      );

      if (!mounted) return;
      setState(() {
        _adjuntos.add({
          'objetoKey': firma['objetoKey'],
          'nombre': archivo.name,
          'mime': 'application/octet-stream',
          'tamano': bytes.length,
        });
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _mensaje = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _mensaje = 'No se pudo adjuntar el archivo.');
    } finally {
      if (mounted) setState(() => _adjuntando = false);
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _enviar({required bool soloGuardar}) async {
    final texto = _texto.text.trim();
    if (texto.length < 5) {
      setState(() => _mensaje = 'Escribe al menos 5 caracteres.');
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
      await cola.encolar(
        entregaId: entregaId,
        actividadId: '${widget.actividad['id']}',
        texto: texto,
        creadaEnCliente: creada,
        adjuntos: _adjuntos,
      );
      if (mounted) setState(() => _mensaje = 'Guardada en el dispositivo. Se enviará al reconectar.');
      if (mounted) setState(() => _enviando = false);
      return;
    }

    try {
      final respuesta = await ref.read(apiClientProvider).postJson('/entregas', cuerpo: {
        'entregaId': entregaId,
        'actividadId': '${widget.actividad['id']}',
        'texto': texto,
        'creadaEnCliente': creada.toUtc().toIso8601String(),
        'adjuntos': _adjuntos,
      });
      if (!mounted) return;
      setState(() => _mensaje = 'Entrega registrada como ${respuesta['estado']}.');
      _texto.clear();
    } on ApiException catch (error) {
      if (error.esSinRed) {
        await cola.encolar(
          entregaId: entregaId,
          actividadId: '${widget.actividad['id']}',
          texto: texto,
          creadaEnCliente: creada,
          adjuntos: _adjuntos,
        );
        if (mounted) setState(() => _mensaje = 'Sin conexión: quedó guardada y se enviará sola.');
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
  }

  @override
  Widget build(BuildContext context) {
    final actividad = widget.actividad;
    final pendientes = ref.read(colaEntregasProvider).pendientes().length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${actividad['titulo']}'),
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tarea · ${actividad['peso']}% del corte ${actividad['corte']}'),
                  if (actividad['instrucciones'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${actividad['instrucciones']}'),
                    ),
                  if (pendientes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Tienes $pendientes entrega(s) guardada(s) sin enviar.',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _texto,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Respuesta de la tarea',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _adjuntando ? null : _adjuntar,
            icon: _adjuntando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: const Text('Adjuntar archivo'),
          ),
          if (_adjuntos.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final adjunto in _adjuntos)
                  Chip(
                    label: Text(''),
                    onDeleted: () => setState(() => _adjuntos.remove(adjunto)),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          if (_mensaje != null) Text(_mensaje!),
          const SizedBox(height: 10),
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
      ),
    );
  }
}
