import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../aulas/presentation/calificaciones_curso_page.dart';

/// Criterios de la evaluación docente (§4.2, D-70).
const Map<String, String> criteriosEvaluacion = {
  'dominio': 'Dominio de la materia',
  'claridad': 'Claridad al explicar',
  'metodologia': 'Metodología',
  'evaluacion': 'Evaluación justa',
  'acompanamiento': 'Acompañamiento',
};

/// Asignaturas del usuario: las inscritas del estudiante (con evaluación docente) o los grupos
/// que dicta el docente, con acceso directo a calificar.
class AsignaturasPage extends ConsumerStatefulWidget {
  const AsignaturasPage({super.key});

  @override
  ConsumerState<AsignaturasPage> createState() => _AsignaturasPageState();
}

class _AsignaturasPageState extends ConsumerState<AsignaturasPage> {
  List<dynamic> _asignaturas = const [];
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
      final asignaturas = await ref.read(repositorioAcademicoProvider).asignaturas();
      if (mounted) setState(() => _asignaturas = asignaturas);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las asignaturas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis asignaturas'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_cargando && _asignaturas.isEmpty)
              const Text('No tienes asignaturas inscritas ni grupos asignados en el periodo activo.'),
            for (final asignatura in _asignaturas)
              if (asignatura is Map) _tarjeta(context, asignatura),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(BuildContext context, Map<dynamic, dynamic> asignatura) {
    final colores = Theme.of(context).colorScheme;
    final esEstudiante = asignatura['inscripcionId'] != null;
    final evaluada = asignatura['evaluada'] == true;
    final aulaId = asignatura['aulaId'] as String?;
    final grupos = (asignatura['grupos'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((grupo) => Map<String, dynamic>.from(grupo))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${asignatura['asignatura']}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        esEstudiante
                            ? '${asignatura['codigo']} · Grupo ${asignatura['grupo']} · ${asignatura['periodo']}'
                            : '${asignatura['codigo']} · ${grupos.length} grupo(s): ${asignatura['grupo']} · ${asignatura['periodo']}',
                        style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text('${asignatura['creditos']} créditos'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              esEstudiante
                  ? 'Docente: ${asignatura['docente'] ?? 'Sin asignar'}'
                  : '${asignatura['estudiantes'] ?? 0} estudiante(s) en ${grupos.length} grupo(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (esEstudiante)
              Align(
                alignment: Alignment.centerRight,
                child: evaluada
                    ? Chip(
                        avatar: Icon(Icons.check_circle_outline, size: 16, color: colores.primary),
                        label: const Text('Evaluación enviada'),
                        visualDensity: VisualDensity.compact,
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _evaluar(asignatura),
                        icon: const Icon(Icons.rate_review_outlined),
                        label: const Text('Evaluar docente'),
                      ),
              )
            else if (aulaId != null)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _calificarCurso(asignatura, grupos),
                  icon: const Icon(Icons.grading_outlined),
                  label: Text(grupos.length > 1 ? 'Calificar por grupo' : 'Calificar entregas'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _calificarCurso(
    Map<dynamic, dynamic> asignatura,
    List<Map<String, dynamic>> grupos,
  ) async {
    if (grupos.length <= 1) {
      final aulaId = grupos.isNotEmpty ? '${grupos.first['aulaId']}' : '${asignatura['aulaId']}';
      if (aulaId.isEmpty || aulaId == 'null') return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CalificacionesCursoPage(aulaId: aulaId, esDocente: true),
        ),
      );
      return;
    }
    final elegido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('Grupos de ${asignatura['asignatura']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final grupo in grupos)
              ListTile(
                dense: true,
                leading: const Icon(Icons.groups_outlined),
                title: Text('Grupo ${grupo['grupo']}'),
                subtitle: Text('${grupo['estudiantes'] ?? 0} estudiante(s)'),
                onTap: () => Navigator.of(contexto).pop(grupo),
              ),
          ],
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Cancelar')),
        ],
      ),
    );
    if (elegido == null || !mounted) return;
    final aulaId = '${elegido['aulaId']}';
    if (aulaId.isEmpty || aulaId == 'null') return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CalificacionesCursoPage(aulaId: aulaId, esDocente: true),
      ),
    );
  }

  Future<void> _evaluar(Map<dynamic, dynamic> asignatura) async {
    final inscripcionId = asignatura['inscripcionId'] as String?;
    if (inscripcionId == null) return;

    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoEvaluacion(asignatura: '${asignatura['asignatura']}'),
    );
    if (datos == null || !mounted) return;

    try {
      await ref.read(repositorioAcademicoProvider).evaluarDocente(
            inscripcionId: inscripcionId,
            respuestas: Map<String, int>.from(datos['respuestas'] as Map),
            comentario: datos['comentario'] as String?,
          );
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias! Tu evaluación quedó registrada.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }
}

class _DialogoEvaluacion extends StatefulWidget {
  const _DialogoEvaluacion({required this.asignatura});

  final String asignatura;

  @override
  State<_DialogoEvaluacion> createState() => _DialogoEvaluacionState();
}

class _DialogoEvaluacionState extends State<_DialogoEvaluacion> {
  final Map<String, int> _respuestas = {
    for (final criterio in criteriosEvaluacion.keys) criterio: 4,
  };
  final _comentario = TextEditingController();

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Evaluar · ${widget.asignatura}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Escala de 1 (muy malo) a 5 (excelente), una evaluación por asignatura.'),
            const SizedBox(height: 10),
            for (final entrada in criteriosEvaluacion.entries) ...[
              Text(entrada.value, style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: 4,
                children: [
                  for (var valor = 1; valor <= 5; valor += 1)
                    ChoiceChip(
                      label: Text('$valor'),
                      selected: _respuestas[entrada.key] == valor,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _respuestas[entrada.key] = valor),
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            TextField(
              controller: _comentario,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'respuestas': Map<String, int>.from(_respuestas),
            'comentario': _comentario.text,
          }),
          child: const Text('Enviar evaluación'),
        ),
      ],
    );
  }
}
