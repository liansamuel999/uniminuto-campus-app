import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Lista de aulas virtuales del usuario (estudiante, docente o admin académico).
class AulasPage extends ConsumerStatefulWidget {
  const AulasPage({super.key});

  @override
  ConsumerState<AulasPage> createState() => _AulasPageState();
}

class _AulasPageState extends ConsumerState<AulasPage> {
  List<dynamic> _aulas = const [];
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
      final aulas = await ref.read(apiClientProvider).getList('/aulas');
      if (mounted) setState(() => _aulas = aulas);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aulas virtuales'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
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
            if (!_cargando && _aulas.isEmpty) const Text('No tienes aulas asignadas todavía.'),
            for (final aula in _aulas)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text('${aula['asignatura']}'),
                  subtitle: Text('${aula['codigo']} · Grupo ${aula['grupo']} · ${aula['periodo']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AulaDetallePage(
                        aulaId: '${aula['id']}',
                        titulo: '${aula['asignatura']}',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Detalle del aula: unidades, contenidos y actividades.
class AulaDetallePage extends ConsumerStatefulWidget {
  const AulaDetallePage({super.key, required this.aulaId, required this.titulo});

  final String aulaId;
  final String titulo;

  @override
  ConsumerState<AulaDetallePage> createState() => _AulaDetallePageState();
}

class _AulaDetallePageState extends ConsumerState<AulaDetallePage> {
  Map<String, dynamic>? _detalle;
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
      final detalle = await ref.read(apiClientProvider).getJson('/aulas/${widget.aulaId}');
      if (mounted) setState(() => _detalle = detalle);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unidades = (_detalle?['unidades'] as List<dynamic>? ?? const []);

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final unidad in unidades)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: CircleAvatar(child: Text('${unidad['numero']}')),
                title: Text('${unidad['titulo']}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final contenido in (unidad['contenidos'] as List<dynamic>? ?? const []))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconoContenido('${contenido['tipo']}')),
                      title: Text('${contenido['titulo']}'),
                      subtitle: Text('${contenido['tipo']}'),
                    ),
                  const Divider(),
                  for (final actividad in (unidad['actividades'] as List<dynamic>? ?? const []))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconoActividad('${actividad['tipo']}')),
                      title: Text('${actividad['titulo']}'),
                      subtitle: Text(
                        '${actividad['tipo']} · ${actividad['peso']}% del corte ${actividad['corte']}'
                        '${actividad['cierraEn'] != null ? ' · cierra ${_fecha(actividad['cierraEn'])}' : ''}',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconoContenido(String tipo) => switch (tipo) {
        'PDF' => Icons.picture_as_pdf_outlined,
        'VIDEO' => Icons.play_circle_outline,
        'ENLACE' => Icons.link,
        _ => Icons.campaign_outlined,
      };

  IconData _iconoActividad(String tipo) => switch (tipo) {
        'TAREA' => Icons.assignment_outlined,
        'CUESTIONARIO' => Icons.quiz_outlined,
        _ => Icons.forum_outlined,
      };

  String _fecha(dynamic valor) {
    final fecha = DateTime.tryParse('$valor')?.toLocal();
    if (fecha == null) return '$valor';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }
}
