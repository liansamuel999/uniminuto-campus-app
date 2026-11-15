import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Vista del docente: califica entregas/tareas y revisa los intentos de cuestionarios (§6.4).
class CalificarPage extends ConsumerStatefulWidget {
  const CalificarPage({super.key, required this.aulaId});

  final String aulaId;

  @override
  ConsumerState<CalificarPage> createState() => _CalificarPageState();
}

class _CalificarPageState extends ConsumerState<CalificarPage> {
  Map<String, dynamic>? _detalle;
  List<dynamic> _filas = const [];
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
      final api = ref.read(apiClientProvider);
      final detalle = await api.getJson('/aulas/${widget.aulaId}');
      final filas = await api.getList('/aulas/${widget.aulaId}/calificaciones');
      if (mounted) {
        setState(() {
          _detalle = detalle;
          _filas = filas;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las calificaciones del aula.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _actividades {
    final resultado = <Map<String, dynamic>>[];
    for (final unidad in (_detalle?['unidades'] as List<dynamic>? ?? const [])) {
      for (final actividad in ((unidad as Map)['actividades'] as List<dynamic>? ?? const [])) {
        resultado.add(Map<String, dynamic>.from(actividad as Map));
      }
    }
    return resultado;
  }

  List<Map<String, dynamic>> _filasDe(String actividadId) => [
        for (final fila in _filas)
          if (fila is Map && '${fila['actividadId']}' == actividadId)
            Map<String, dynamic>.from(fila),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calificar'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!),
            ),
          if (!_cargando && _error == null && _actividades.isEmpty)
            const Text('El aula todavía no tiene actividades para calificar.'),
          for (final actividad in _actividades) _tarjetaActividad(actividad),
        ],
      ),
    );
  }

  Widget _tarjetaActividad(Map<String, dynamic> actividad) {
    final filas = _filasDe('${actividad['id']}');
    final tipo = '${actividad['tipo']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(
          switch (tipo) {
            'TAREA' => Icons.assignment_outlined,
            'CUESTIONARIO' => Icons.quiz_outlined,
            _ => Icons.forum_outlined,
          },
        ),
        title: Text('${actividad['titulo']}'),
        subtitle: Text('$tipo · ${actividad['peso']}% del corte ${actividad['corte']}'),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: [
          if (tipo == 'CUESTIONARIO')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _revisarIntentos(actividad),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar intentos de los estudiantes'),
              ),
            ),
          if (filas.isEmpty) const ListTile(dense: true, title: Text('Sin estudiantes en este grupo.')),
          for (final fila in filas)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline, size: 20),
              title: Text('${fila['estudiante']}'),
              subtitle: Text(
                fila['nota'] == null
                    ? 'Sin calificar'
                    : 'Nota ${fila['nota']} / ${fila['notaMaxima']}'
                        '${fila['retroalimentacion'] == null ? '' : ' · ${fila['retroalimentacion']}'}',
              ),
              trailing: IconButton(
                tooltip: 'Calificar',
                onPressed: () => _calificar(actividad, fila),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _calificar(Map<String, dynamic> actividad, Map<String, dynamic> fila) async {
    String? entregaTexto;
    if ('${actividad['tipo']}' == 'TAREA') {
      entregaTexto = await _textoDeEntrega('${actividad['id']}', '${fila['inscripcionId']}');
    }
    if (!mounted) return;

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoCalificar(
        estudiante: '${fila['estudiante']}',
        actividad: '${actividad['titulo']}',
        notaMaxima: (actividad['notaMaxima'] as num?)?.toDouble() ?? 5,
        notaActual: (fila['nota'] as num?)?.toDouble(),
        retroActual: fila['retroalimentacion'] as String?,
        entregaTexto: entregaTexto,
      ),
    );
    if (resultado == null || !mounted) return;

    try {
      await ref.read(apiClientProvider).putJson(
        '/calificaciones',
        cuerpo: {
          'actividadId': '${actividad['id']}',
          'inscripcionId': '${fila['inscripcionId']}',
          'nota': resultado['nota'],
          if (resultado['retroalimentacion'] != null) 'retroalimentacion': resultado['retroalimentacion'],
        },
      );
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calificación guardada para ${fila['estudiante']}.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  Future<String?> _textoDeEntrega(String actividadId, String inscripcionId) async {
    try {
      final entregas = await ref.read(apiClientProvider).getList('/actividades/$actividadId/entregas');
      for (final entrega in entregas) {
        if (entrega is Map && '${entrega['inscripcionId']}' == inscripcionId) {
          final texto = '${entrega['texto'] ?? ''}'.trim();
          return texto.isEmpty ? '(entrega sin texto)' : texto;
        }
      }
      return null;
    } on ApiException {
      return null;
    }
  }

  Future<void> _revisarIntentos(Map<String, dynamic> actividad) async {
    try {
      final intentos = await ref.read(apiClientProvider).getList('/cuestionarios/${actividad['id']}/intentos');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (contexto) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Intentos · ${actividad['titulo']}', style: Theme.of(contexto).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (intentos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Ningún estudiante ha respondido este cuestionario todavía.'),
              ),
            for (final intento in intentos)
              if (intento is Map)
                ListTile(
                  leading: CircleAvatar(child: Text('${intento['puntaje']}')),
                  title: Text('${intento['estudiante']}'),
                  subtitle: Text('Enviado el ${_fechaCorta('${intento['enviadoEn']}')}'),
                ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }
}

class _DialogoCalificar extends StatefulWidget {
  const _DialogoCalificar({
    required this.estudiante,
    required this.actividad,
    required this.notaMaxima,
    this.notaActual,
    this.retroActual,
    this.entregaTexto,
  });

  final String estudiante;
  final String actividad;
  final double notaMaxima;
  final double? notaActual;
  final String? retroActual;
  final String? entregaTexto;

  @override
  State<_DialogoCalificar> createState() => _DialogoCalificarState();
}

class _DialogoCalificarState extends State<_DialogoCalificar> {
  late final TextEditingController _nota =
      TextEditingController(text: widget.notaActual?.toStringAsFixed(2) ?? '');
  late final TextEditingController _retro = TextEditingController(text: widget.retroActual ?? '');
  String? _error;

  @override
  void dispose() {
    _nota.dispose();
    _retro.dispose();
    super.dispose();
  }

  void _guardar() {
    final nota = double.tryParse(_nota.text.trim().replaceAll(',', '.'));
    if (nota == null || nota < 0 || nota > widget.notaMaxima) {
      setState(() => _error = 'La nota debe estar entre 0 y ${widget.notaMaxima}');
      return;
    }
    final retro = _retro.text.trim();
    Navigator.of(context).pop({
      'nota': nota,
      if (retro.isNotEmpty) 'retroalimentacion': retro,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Calificar · ${widget.estudiante}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.actividad, style: Theme.of(context).textTheme.bodySmall),
            if (widget.entregaTexto != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.entregaTexto!, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _nota,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Nota (0 – ${widget.notaMaxima})',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _retro,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Retroalimentación (opcional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar nota')),
      ],
    );
  }
}

String _fechaCorta(String iso) {
  final fecha = DateTime.tryParse(iso)?.toLocal();
  if (fecha == null) return iso;
  return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} '
      '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
}
