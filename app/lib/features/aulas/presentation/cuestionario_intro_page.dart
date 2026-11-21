import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import 'cuestionario_page.dart';

/// Antesala del cuestionario: título, descripción, intentos disponibles y botón para iniciarlo.
class CuestionarioIntroPage extends ConsumerStatefulWidget {
  const CuestionarioIntroPage({
    super.key,
    required this.actividadId,
    required this.titulo,
    this.descripcion,
    this.cierraEn,
    this.recursos = const [],
  });

  final String actividadId;
  final String titulo;
  final String? descripcion;
  final DateTime? cierraEn;
  /// Archivos/materiales propios de la actividad.
  final List<Map<String, dynamic>> recursos;

  @override
  ConsumerState<CuestionarioIntroPage> createState() => _CuestionarioIntroPageState();
}

class _CuestionarioIntroPageState extends ConsumerState<CuestionarioIntroPage> {
  Map<String, dynamic>? _cuestionario;
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
      final datos = await ref.read(apiClientProvider).getJson('/cuestionarios/${widget.actividadId}');
      if (mounted) setState(() => _cuestionario = datos);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrirRecurso(String objetoKey) async {
    if (objetoKey.isEmpty) return;
    try {
      final url = await ref.read(repositorioAcademicoProvider).urlDeObjeto(objetoKey);
      if (!mounted) return;
      await abrirEnlace(context, url);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  Future<void> _iniciar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CuestionarioPage(
          actividadId: widget.actividadId,
          titulo: widget.titulo,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _verRevision() async {
    try {
      final intento = await ref
          .read(repositorioAcademicoProvider)
          .miIntento(widget.actividadId);
      if (!mounted) return;
      if (intento == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay un intento registrado para revisar.')),
        );
        return;
      }
      final detalle = (intento['detalle'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((fila) => Map<String, dynamic>.from(fila))
          .toList();
      await showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: Text('Revisión · ${intento['puntaje']} / ${_cuestionario?['notaMaxima'] ?? 5}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (indice, respuesta) in detalle.indexed)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                respuesta['acerto'] == true ? Icons.check_circle : Icons.cancel_outlined,
                                color: respuesta['acerto'] == true ? Colors.green : Theme.of(contexto).colorScheme.error,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${indice + 1}. ${respuesta['enunciado']}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          for (final opcion in ((respuesta['opciones'] as List<dynamic>?) ?? const [])
                              .whereType<Map>())
                            Text(
                              '${((respuesta['elegidas'] as List<dynamic>?) ?? const []).contains('${opcion['id']}') ? '✔ Tu respuesta' : '   '} '
                              '${opcion['texto']}${opcion['esCorrecta'] == true ? ' (correcta)' : ''}',
                              style: TextStyle(
                                color: opcion['esCorrecta'] == true
                                    ? Colors.green
                                    : (((respuesta['elegidas'] as List<dynamic>?) ?? const [])
                                            .contains('${opcion['id']}'))
                                        ? Theme.of(contexto).colorScheme.error
                                        : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Cerrar')),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final yaRespondido = _cuestionario?['yaRespondido'] == true;
    final preguntas = (_cuestionario?['preguntas'] as List<dynamic>? ?? const []).length;
    final cerrado = widget.cierraEn != null && DateTime.now().isAfter(widget.cierraEn!);

    return Scaffold(
      appBar: AppBar(title: const Text('Cuestionario')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.titulo,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('${_cuestionario?['notaMaxima'] ?? 5} puntos · $preguntas preguntas'),
                  if (widget.cierraEn != null)
                    Text('Disponible hasta ${fechaHoraCorta(widget.cierraEn)}'),
                  if ((widget.descripcion ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('${widget.descripcion}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.recursos.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Materiales del cuestionario', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final recurso in widget.recursos)
                          ActionChip(
                            avatar: const Icon(Icons.attach_file, size: 16),
                            label: Text('${recurso['nombre'] ?? 'archivo'}'),
                            onPressed: () => _abrirRecurso('${recurso['objetoKey'] ?? ''}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (yaRespondido)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colores.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline),
                      SizedBox(width: 8),
                      Expanded(child: Text('Ya respondiste este cuestionario. Tu nota ya está registrada.')),
                    ],
                  ),
                ),
                if (_cuestionario?['revisionPermitida'] == true) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _verRevision,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Ver revisión de mis respuestas'),
                  ),
                ],
              ],
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cerrado
                    ? colores.errorContainer.withValues(alpha: 0.5)
                    : colores.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                cerrado
                    ? 'El cuestionario cerró${widget.cierraEn == null ? '' : ' el ${fechaHoraCorta(widget.cierraEn)}'}. Ya no se aceptan respuestas.'
                    : 'Tienes un único intento. Si sales antes de enviarlo, no se registra y podrás '
                        'volver a entrar; una vez enviado no se puede repetir.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cuestionario == null || cerrado ? null : _iniciar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar intento'),
            ),
          ],
        ],
      ),
    );
  }
}
