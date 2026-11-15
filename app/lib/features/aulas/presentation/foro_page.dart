import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../data/comunicacion_repository.dart';

/// Foro de una actividad (`foroId` = `actividad_id`, D-47). Hilos y mensajes viven en Firestore.
class ForoPage extends ConsumerWidget {
  const ForoPage({super.key, required this.foroId, required this.aulaId, required this.titulo});

  final String foroId;
  final String aulaId;
  final String titulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final repo = ref.watch(comunicacionRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Foro')),
      floatingActionButton: sesion == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirNuevoHilo(context, ref, sesion),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Nuevo hilo'),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Hilos de discusión del aula · datos de muestra',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<HiloForo>>(
              stream: repo.hilos(foroId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _Aviso(
                    icono: Icons.cloud_off_outlined,
                    texto: 'No se pudieron leer los hilos. Revisa la conexión '
                        'o que las reglas de Firestore estén desplegadas.',
                  );
                }
                final hilos = snapshot.data ?? const <HiloForo>[];
                if (hilos.isEmpty) {
                  return const _Aviso(
                    icono: Icons.forum_outlined,
                    texto: 'Todavía no hay hilos en este foro. Crea el primero.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: hilos.length,
                  itemBuilder: (context, indice) {
                    final hilo = hilos[indice];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(hilo.titulo),
                        subtitle: Text(
                          '${hilo.autorNombre}'
                          '${hilo.creadoEn == null ? '' : ' · ${_fechaCorta(hilo.creadoEn!)}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => HiloForoPage(foroId: foroId, aulaId: aulaId, hilo: hilo),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirNuevoHilo(BuildContext context, WidgetRef ref, Sesion sesion) async {
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
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    final tituloHilo = controlador.text.trim();
    controlador.dispose();
    if (confirmado != true || tituloHilo.length < 3) return;
    try {
      await ref.read(comunicacionRepositoryProvider).crearHilo(
            foroId: foroId,
            aulaId: aulaId,
            autorUid: sesion.uid,
            autorNombre: sesion.perfil.nombreCompleto,
            titulo: tituloHilo,
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo crear el hilo. ¿Estás conectado?')),
        );
      }
    }
  }
}

/// Hilo abierto: mensajes en tiempo real y caja de respuesta.
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
  bool _enviando = false;

  @override
  void dispose() {
    _mensaje.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _mensaje.text.trim();
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (texto.length < 2 || sesion == null) return;
    setState(() => _enviando = true);
    try {
      await ref.read(comunicacionRepositoryProvider).enviarMensaje(
            foroId: widget.foroId,
            hiloId: widget.hilo.id,
            aulaId: widget.aulaId,
            autorUid: sesion.uid,
            autorNombre: sesion.perfil.nombreCompleto,
            texto: texto,
          );
      _mensaje.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo enviar el mensaje.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(comunicacionRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.hilo.titulo, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MensajeForo>>(
              stream: repo.mensajes(widget.foroId, widget.hilo.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _Aviso(
                    icono: Icons.cloud_off_outlined,
                    texto: 'No se pudieron leer los mensajes de este hilo.',
                  );
                }
                final mensajes = snapshot.data ?? const <MensajeForo>[];
                if (mensajes.isEmpty) {
                  return const _Aviso(icono: Icons.chat_bubble_outline, texto: 'Sé el primero en responder.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: mensajes.length,
                  itemBuilder: (context, indice) {
                    final mensaje = mensajes[indice];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(mensaje.texto),
                        subtitle: Text(
                          '${mensaje.autorNombre}'
                          '${mensaje.creadoEn == null ? '' : ' · ${_fechaCorta(mensaje.creadoEn!)}'}',
                        ),
                      ),
                    );
                  },
                );
              },
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
                        border: OutlineInputBorder(),
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

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 44, color: colores.outline),
            const SizedBox(height: 10),
            Text(texto, textAlign: TextAlign.center, style: TextStyle(color: colores.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

String _fechaCorta(DateTime fecha) {
  final local = fecha.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
