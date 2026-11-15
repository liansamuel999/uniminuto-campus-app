import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../data/comunicacion_repository.dart';

/// Anuncios del aula (`anuncios/{aulaId}/items`, D-48).
///
/// Los publica el docente del aula; si marca «importante», la app llama a
/// `POST /anuncios/{id}/replicar-correo` para llenar la bandeja simulada de los estudiantes.
class AnunciosPage extends ConsumerWidget {
  const AnunciosPage({super.key, required this.aulaId, required this.puedePublicar});

  final String aulaId;
  final bool puedePublicar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(comunicacionRepositoryProvider);
    final sesion = ref.watch(sesionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Anuncios')),
      floatingActionButton: puedePublicar && sesion != null
          ? FloatingActionButton.extended(
              onPressed: () => _publicar(context, ref, sesion),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Publicar'),
            )
          : null,
      body: StreamBuilder<List<AnuncioAula>>(
        stream: repo.anuncios(aulaId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const _Aviso(
              texto: 'No se pudieron leer los anuncios. Revisa la conexión '
                  'o que las reglas de Firestore estén desplegadas.',
            );
          }
          final anuncios = snapshot.data ?? const <AnuncioAula>[];
          if (anuncios.isEmpty) {
            return const _Aviso(texto: 'Todavía no hay anuncios en este aula.');
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: anuncios.length,
            itemBuilder: (context, indice) {
              final anuncio = anuncios[indice];
              return Card(
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
                            color: anuncio.importante
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
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
                        '${anuncio.creadoEn == null ? '' : ' · ${_fechaCorta(anuncio.creadoEn!)}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _publicar(BuildContext context, WidgetRef ref, Sesion sesion) async {
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
            aulaId: aulaId,
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
          cuerpo: {'aulaId': aulaId, 'asunto': titulo, 'cuerpo': cuerpo},
        );
        mensaje = 'Anuncio publicado y replicado a ${respuesta['creados'] ?? 0} estudiante(s).';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo publicar el anuncio. ¿Estás conectado?')),
        );
      }
    }
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
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

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

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
            Icon(Icons.campaign_outlined, size: 44, color: colores.outline),
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
