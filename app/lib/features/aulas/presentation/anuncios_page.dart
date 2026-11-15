import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/formato.dart';
import '../data/comunicacion_repository.dart';

/// Anuncios del aula (servidos por la API sobre Firestore, D-48 y D-78).
///
/// Los publica el docente del aula; si marca «importante», la app llama a
/// `POST /anuncios/{id}/replicar-correo` para llenar la bandeja simulada de los estudiantes.
class AnunciosPage extends ConsumerStatefulWidget {
  const AnunciosPage({super.key, required this.aulaId, required this.puedePublicar});

  final String aulaId;
  final bool puedePublicar;

  @override
  ConsumerState<AnunciosPage> createState() => _AnunciosPageState();
}

class _AnunciosPageState extends ConsumerState<AnunciosPage> {
  List<AnuncioAula> _anuncios = const [];
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
      final anuncios = await ref.read(comunicacionRepositoryProvider).anuncios(widget.aulaId);
      if (mounted) setState(() => _anuncios = anuncios);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los anuncios.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _publicar() async {
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (sesion == null) return;
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _DialogoAnuncio(),
    );
    if (datos == null) return;

    final titulo = '${datos['titulo']}';
    final cuerpo = '${datos['cuerpo']}';
    final importante = datos['importante'] == true;

    try {
      final anuncioId = await ref.read(comunicacionRepositoryProvider).publicarAnuncio(
            aulaId: widget.aulaId,
            autorUid: sesion.uid,
            autorNombre: sesion.perfil.nombreCompleto,
            titulo: titulo,
            cuerpo: cuerpo,
            importante: importante,
          );

      var mensaje = 'Anuncio publicado.';
      if (importante) {
        final respuesta = await ref.read(apiClientProvider).postJson(
          '/anuncios/$anuncioId/replicar-correo',
          cuerpo: {'aulaId': widget.aulaId, 'asunto': titulo, 'cuerpo': cuerpo},
        );
        mensaje = 'Anuncio publicado y replicado a ${respuesta['creados'] ?? 0} estudiante(s).';
      }
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
      }
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
        title: const Text('Anuncios'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: widget.puedePublicar
          ? FloatingActionButton.extended(
              onPressed: _publicar,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Publicar'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
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
            if (!_cargando && _error == null && _anuncios.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Todavía no hay anuncios en este aula.'),
              ),
            for (final anuncio in _anuncios)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            anuncio.importante ? Icons.priority_high : Icons.campaign_outlined,
                            color: anuncio.importante ? colores.error : colores.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              anuncio.titulo,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(anuncio.cuerpo),
                      const SizedBox(height: 8),
                      Text(
                        '${anuncio.autorNombre}'
                        '${anuncio.creadoEn == null ? '' : ' · ${fechaHoraCorta(anuncio.creadoEn)}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialogoAnuncio extends StatefulWidget {
  const _DialogoAnuncio();

  @override
  State<_DialogoAnuncio> createState() => _DialogoAnuncioState();
}

class _DialogoAnuncioState extends State<_DialogoAnuncio> {
  final _titulo = TextEditingController();
  final _cuerpo = TextEditingController();
  bool _importante = true;

  @override
  void dispose() {
    _titulo.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo anuncio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titulo,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            TextField(
              controller: _cuerpo,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Mensaje'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _importante,
              onChanged: (valor) => setState(() => _importante = valor),
              title: const Text('Marcar como importante'),
              subtitle: const Text('Se replica por correo simulado a los estudiantes'),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final titulo = _titulo.text.trim();
            final cuerpo = _cuerpo.text.trim();
            if (titulo.length < 3 || cuerpo.length < 3) return;
            Navigator.of(context).pop({
              'titulo': titulo,
              'cuerpo': cuerpo,
              'importante': _importante,
            });
          },
          child: const Text('Publicar'),
        ),
      ],
    );
  }
}
