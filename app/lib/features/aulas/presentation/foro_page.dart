import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import '../data/comunicacion_repository.dart';

/// Foro de una actividad (`foroId` = `actividad_id`, D-47).
///
/// Las pantallas leen y escriben a través de la API, que valida la pertenencia al aula y usa
/// Firestore con el Admin SDK (D-78). Se refresca al abrir, al deslizar y después de publicar.
class ForoPage extends ConsumerStatefulWidget {
  const ForoPage({super.key, required this.foroId, required this.aulaId, required this.titulo});

  final String foroId;
  final String aulaId;
  final String titulo;

  @override
  ConsumerState<ForoPage> createState() => _ForoPageState();
}

class _ForoPageState extends ConsumerState<ForoPage> {
  List<HiloForo> _hilos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final hilos = await ref.read(comunicacionRepositoryProvider).hilos(widget.foroId);
      if (mounted) setState(() => _hilos = hilos);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los hilos del foro.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevoHilo() async {
    final controlador = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Nuevo hilo'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Título del hilo'),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(contexto).pop(true), child: const Text('Crear')),
        ],
      ),
    );
    final titulo = controlador.text.trim();
    controlador.dispose();
    if (confirmado != true || titulo.length < 3) return;
    try {
      await ref.read(comunicacionRepositoryProvider).crearHilo(
            foroId: widget.foroId,
            aulaId: widget.aulaId,
            autorUid: '',
            autorNombre: '',
            titulo: titulo,
          );
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foro'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoHilo,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Nuevo hilo'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(widget.titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Hilos de discusión del aula',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colores.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!),
              ),
            if (!_cargando && _error == null && _hilos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Todavía no hay hilos en este foro. Crea el primero.'),
              ),
            for (final hilo in _hilos)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(hilo.titulo),
                  subtitle: Text(
                    '${hilo.autorNombre}'
                    '${hilo.creadoEn == null ? '' : ' · ${fechaHoraCorta(hilo.creadoEn)}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HiloForoPage(
                          foroId: widget.foroId,
                          aulaId: widget.aulaId,
                          hilo: hilo,
                        ),
                      ),
                    );
                    await _cargar();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hilo abierto: mensajes y caja de respuesta.
class HiloForoPage extends ConsumerStatefulWidget {
  const HiloForoPage({super.key, required this.foroId, required this.aulaId, required this.hilo});

  final String foroId;
  final String aulaId;
  final HiloForo hilo;

  @override
  ConsumerState<HiloForoPage> createState() => _HiloForoPageState();
}

class _HiloForoPageState extends ConsumerState<HiloForoPage> {
  final _mensaje = TextEditingController();
  List<MensajeForo> _mensajes = const [];
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _mensaje.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final mensajes = await ref
          .read(comunicacionRepositoryProvider)
          .mensajes(widget.foroId, widget.hilo.id);
      if (mounted) setState(() => _mensajes = mensajes);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _enviar() async {
    final texto = _mensaje.text.trim();
    if (texto.length < 2) return;
    setState(() => _enviando = true);
    try {
      await ref.read(comunicacionRepositoryProvider).enviarMensaje(
            foroId: widget.foroId,
            hiloId: widget.hilo.id,
            aulaId: widget.aulaId,
            autorUid: '',
            autorNombre: '',
            texto: texto,
          );
      _mensaje.clear();
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.hilo.titulo, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_cargando)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                  if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
                  if (!_cargando && _error == null && _mensajes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Sé el primero en responder.'),
                    ),
                  for (final mensaje in _mensajes)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(mensaje.texto),
                        subtitle: Text(
                          '${mensaje.autorNombre}'
                          '${mensaje.creadoEn == null ? '' : ' · ${fechaHoraCorta(mensaje.creadoEn)}'}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mensaje,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
