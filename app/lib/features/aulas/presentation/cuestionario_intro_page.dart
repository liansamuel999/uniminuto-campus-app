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
  });

  final String actividadId;
  final String titulo;
  final String? descripcion;
  final DateTime? cierraEn;

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

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final yaRespondido = _cuestionario?['yaRespondido'] == true;
    final preguntas = (_cuestionario?['preguntas'] as List<dynamic>? ?? const []).length;

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
          if (yaRespondido)
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
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colores.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Tienes un único intento. Si sales antes de enviarlo, no se registra y podrás '
                'volver a entrar; una vez enviado no se puede repetir.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cuestionario == null ? null : _iniciar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar intento'),
            ),
          ],
        ],
      ),
    );
  }
}
