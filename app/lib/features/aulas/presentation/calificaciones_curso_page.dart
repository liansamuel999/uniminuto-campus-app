import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import 'actividad_docente_page.dart';

/// Calificaciones de un curso: el estudiante ve sus notas por actividad y corte;
/// el docente ve las actividades y entra a calificar/ver entregas de cada una.
class CalificacionesCursoPage extends ConsumerWidget {
  const CalificacionesCursoPage({super.key, required this.aulaId, required this.esDocente});

  final String aulaId;
  final bool esDocente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (esDocente) return _CalificacionesDocentePage(aulaId: aulaId);
    return _CalificacionesEstudiantePage(aulaId: aulaId);
  }
}

class _CalificacionesDocentePage extends ConsumerStatefulWidget {
  const _CalificacionesDocentePage({required this.aulaId});

  final String aulaId;

  @override
  ConsumerState<_CalificacionesDocentePage> createState() => _CalificacionesDocentePageState();
}

class _CalificacionesDocentePageState extends ConsumerState<_CalificacionesDocentePage> {
  List<Map<String, dynamic>> _actividades = const [];
  List<Map<String, dynamic>> _calificaciones = const [];
  String _docente = '';
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
      final calificaciones = await api.getList('/aulas/${widget.aulaId}/calificaciones');
      if (!mounted) return;
      final actividades = <Map<String, dynamic>>[];
      for (final unidad in (detalle['unidades'] as List<dynamic>? ?? const [])) {
        for (final actividad in ((unidad as Map)['actividades'] as List<dynamic>? ?? const [])) {
          actividades.add(Map<String, dynamic>.from(actividad as Map));
        }
      }
      setState(() {
        _docente = '${detalle['docente'] ?? ''}';
        _actividades = actividades;
        _calificaciones = calificaciones
            .whereType<Map>()
            .map((fila) => Map<String, dynamic>.from(fila))
            .toList();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calificar el curso'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
          for (final actividad in _actividades) _tarjetaActividad(context, actividad),
        ],
      ),
    );
  }

  Widget _tarjetaActividad(BuildContext context, Map<String, dynamic> actividad) {
    final filas = _calificaciones
        .where((fila) => '${fila['actividadId']}' == '${actividad['id']}')
        .toList();
    final calificados = filas.where((fila) => fila['nota'] != null).length;
    final cierra = DateTime.tryParse('${actividad['cierraEn']}');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(switch ('${actividad['tipo']}') {
          'TAREA' => Icons.assignment_outlined,
          'CUESTIONARIO' => Icons.quiz_outlined,
          _ => Icons.forum_outlined,
        }),
        title: Text('${actividad['titulo']}'),
        subtitle: Text(
          '${actividad['tipo']} · ${actividad['peso']}% del corte ${actividad['corte']}\n'
          '$calificados de ${filas.length} calificados'
          '${cierra == null ? '' : ' · cierra ${fechaHoraCorta(cierra)}'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ActividadDocentePage(
                actividad: actividad,
                aulaId: widget.aulaId,
                docenteNombre: _docente,
              ),
            ),
          );
          await _cargar();
        },
      ),
    );
  }
}

class _CalificacionesEstudiantePage extends ConsumerStatefulWidget {
  const _CalificacionesEstudiantePage({required this.aulaId});

  final String aulaId;

  @override
  ConsumerState<_CalificacionesEstudiantePage> createState() =>
      _CalificacionesEstudiantePageState();
}

class _CalificacionesEstudiantePageState extends ConsumerState<_CalificacionesEstudiantePage> {
  List<Map<String, dynamic>> _asignaturas = const [];
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
      final datos = await ref.read(repositorioAcademicoProvider).misCalificaciones(widget.aulaId);
      if (mounted) {
        setState(() {
          _asignaturas = datos
              .whereType<Map>()
              .map((fila) => Map<String, dynamic>.from(fila))
              .toList();
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Calificaciones')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
            if (!_cargando && _asignaturas.isEmpty)
              const Text('Todavía no tienes notas en este curso.'),
            for (final asignatura in _asignaturas) _tarjeta(context, asignatura),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(BuildContext context, Map<String, dynamic> asignatura) {
    final colores = Theme.of(context).colorScheme;
    final cortes = (asignatura['cortes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((corte) => Map<String, dynamic>.from(corte))
        .toList();
    final publicada = asignatura['definitivaPublicada'] == true;
    final definitiva = (asignatura['definitiva'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${asignatura['asignatura']}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(publicada ? 'Definitiva ${definitiva.toStringAsFixed(2)}' : 'En curso'),
                  backgroundColor:
                      publicada ? (definitiva >= 3 ? const Color(0xFFE3F5E8) : colores.errorContainer) : colores.surfaceContainerHighest,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final corte in cortes) ...[
              Row(
                children: [
                  Text('Corte ${corte['numero']} · ${corte['peso']}%',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    corte['nota'] == null ? 'Sin nota' : (corte['nota'] as num).toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (corte['cerrado'] != true)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('(en curso)', style: TextStyle(fontSize: 11, color: colores.onSurfaceVariant)),
                    ),
                ],
              ),
              for (final actividad in (corte['actividades'] as List<dynamic>? ?? const []))
                if (actividad is Map)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${actividad['titulo']} · ${actividad['peso']}%',
                            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
                          ),
                        ),
                        Text(
                          actividad['nota'] == null
                              ? '—'
                              : (actividad['nota'] as num).toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: actividad['nota'] == null ? colores.outline : colores.onSurface,
                          ),
                        ),
                        if (actividad['cierraEn'] != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              'cierra ${fechaCorta(DateTime.tryParse('${actividad['cierraEn']}'))}',
                              style: TextStyle(fontSize: 10, color: colores.outline),
                            ),
                          ),
                      ],
                    ),
                  ),
              if (corte != cortes.last) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}
