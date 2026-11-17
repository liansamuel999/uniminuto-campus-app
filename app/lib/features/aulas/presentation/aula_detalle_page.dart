import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import 'actividad_docente_page.dart';
import 'actividad_editor_page.dart';
import 'anuncios_page.dart';
import 'aula_editor.dart';
import 'calificaciones_curso_page.dart';
import 'contenido_editor_page.dart';
import 'contenido_visor.dart';
import 'cuestionario_intro_page.dart';
import 'foro_page.dart';
import 'participantes_page.dart';
import 'tarea_page.dart';

/// Detalle del curso: contenidos, actividades, participantes y notas.
///
/// La misma pantalla sirve al estudiante (consulta, entregas e intentos) y al docente dueño
/// (edición del aula, contenidos y actividades, calificación y revisión de intentos).
class AulaDetallePage extends ConsumerStatefulWidget {
  const AulaDetallePage({
    super.key,
    required this.aulaId,
    required this.titulo,
    this.actividadInicialId,
  });

  final String aulaId;
  final String titulo;
  final String? actividadInicialId;

  @override
  ConsumerState<AulaDetallePage> createState() => _AulaDetallePageState();
}

class _AulaDetallePageState extends ConsumerState<AulaDetallePage> {
  Map<String, dynamic>? _detalle;
  bool _cargando = true;
  bool _abrioActividadInicial = false;
  String? _error;

  bool get _esDocente => '${_detalle?['rolEnAula']}' == 'DOCENTE';

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
      if (!mounted) return;
      setState(() => _detalle = detalle);
      final actividadInicial = widget.actividadInicialId;
      if (!_abrioActividadInicial && actividadInicial != null) {
        _abrioActividadInicial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _abrirActividadPorId(actividadInicial);
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir el curso.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _unidades =>
      (_detalle?['unidades'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((unidad) => Map<String, dynamic>.from(unidad))
          .toList();

  void _abrirActividadPorId(String actividadId) {
    for (final unidad in _unidades) {
      for (final actividad in (unidad['actividades'] as List<dynamic>? ?? const [])) {
        if (actividad is Map && '${actividad['id']}' == actividadId) {
          _abrirActividad(Map<String, dynamic>.from(actividad));
          return;
        }
      }
    }
    _aviso('La actividad ya no está disponible en este curso.');
  }

  void _abrirActividad(Map<String, dynamic> actividad) {
    if (_esDocente) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActividadDocentePage(
            actividad: actividad,
            aulaId: widget.aulaId,
            docenteNombre: '${_detalle?['docente'] ?? ''}',
          ),
        ),
      );
      return;
    }
    switch ('${actividad['tipo']}') {
      case 'TAREA':
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TareaPage(actividad: actividad)),
        );
      case 'CUESTIONARIO':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CuestionarioIntroPage(
              actividadId: '${actividad['id']}',
              titulo: '${actividad['titulo']}',
              descripcion: actividad['instrucciones'] as String?,
              cierraEn: DateTime.tryParse('${actividad['cierraEn']}'),
              recursos: ((actividad['recursos'] as List<dynamic>?) ?? const [])
                  .whereType<Map>()
                  .map((recurso) => Map<String, dynamic>.from(recurso))
                  .toList(),
            ),
          ),
        );
      case 'FORO':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ForoPage(
              foroId: '${actividad['id']}',
              aulaId: widget.aulaId,
              titulo: '${actividad['titulo']}',
            ),
          ),
        );
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_detalle?['asignatura'] ?? widget.titulo}'),
        actions: [
          IconButton(
            tooltip: 'Anuncios del aula',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AnunciosPage(aulaId: widget.aulaId, puedePublicar: _esDocente),
              ),
            ),
            icon: const Icon(Icons.campaign_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
            if (_detalle != null) _encabezado(context, colores),
            if (_detalle != null) _accionesCurso(context),
            const SizedBox(height: 12),
            for (final unidad in _unidades) _tarjetaUnidad(context, unidad),
            if (_esDocente)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => nuevaUnidadDialog(context, ref, widget.aulaId, _cargar),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir unidad'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _encabezado(BuildContext context, ColorScheme colores) {
    final detalle = _detalle!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${detalle['asignatura']}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${detalle['codigo']} · Curso ${detalle['codigoCurso'] ?? ''} · ${detalle['periodo']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Docente: ${detalle['docente'] ?? 'Sin asignar'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accionesCurso(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ParticipantesPage(aulaId: widget.aulaId, esDocente: _esDocente),
                ),
              ),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Participantes'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CalificacionesCursoPage(aulaId: widget.aulaId, esDocente: _esDocente),
                ),
              ),
              icon: const Icon(Icons.grading_outlined),
              label: Text(_esDocente ? 'Calificar' : 'Calificaciones'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaUnidad(BuildContext context, Map<String, dynamic> unidad) {
    final contenidos = (unidad['contenidos'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((contenido) => Map<String, dynamic>.from(contenido))
        .toList();
    final actividades = (unidad['actividades'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((actividad) => Map<String, dynamic>.from(actividad))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(child: Text('${unidad['numero']}')),
        title: Text('${unidad['titulo']}'),
        subtitle: Text('Corte ${unidad['numero'] == 1 ? 1 : 2} · ${actividades.length} actividad(es)'),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          if (contenidos.isEmpty && actividades.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('Sin contenidos todavía.')),
          for (final contenido in contenidos)
            ListTile(
              dense: true,
              leading: Icon(_iconoContenido('${contenido['tipo']}')),
              title: Text('${contenido['titulo']}'),
              subtitle: Text('${contenido['tipo']} · toca para abrir'),
              trailing: _esDocente
                  ? PopupMenuButton<String>(
                      onSelected: (valor) {
                        if (valor == 'editar') {
                          _abrirEditorContenido(contenido, unidadId: '${unidad['id']}');
                        }
                        if (valor == 'eliminar') _eliminarContenido(contenido);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                      ],
                    )
                  : const Icon(Icons.open_in_new, size: 16),
              onTap: () => abrirContenido(context, ref, contenido, esDocente: _esDocente),
            ),
          if (_esDocente)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _abrirEditorContenido(null, unidadId: '${unidad['id']}'),
                icon: const Icon(Icons.attach_file),
                label: const Text('Añadir contenido'),
              ),
            ),
          const Divider(),
          for (final actividad in actividades)
            ListTile(
              dense: true,
              leading: Icon(_iconoActividad('${actividad['tipo']}')),
              title: Text('${actividad['titulo']}'),
              subtitle: Text(
                '${actividad['tipo']} · ${actividad['peso']}% · '
                '${actividad['cierraEn'] == null ? 'sin fecha límite' : 'vence ${fechaHoraCorta(DateTime.tryParse('${actividad['cierraEn']}'))}'}',
              ),
              trailing: _esDocente
                  ? PopupMenuButton<String>(
                      onSelected: (valor) {
                        if (valor == 'editar') _abrirEditorActividad(actividad, unidadId: '${unidad['id']}');
                        if (valor == 'eliminar') _eliminarActividad(actividad);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                      ],
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => _abrirActividad(actividad),
            ),
          if (_esDocente)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _abrirEditorActividad(null, unidadId: '${unidad['id']}'),
                icon: const Icon(Icons.add_task),
                label: const Text('Añadir actividad'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirEditorContenido(
    Map<String, dynamic>? contenido, {
    String? unidadId,
  }) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ContenidoEditorPage(
          unidadId: unidadId ?? '${contenido?['unidadId'] ?? ''}',
          contenidoActual: contenido,
        ),
      ),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _abrirEditorActividad(
    Map<String, dynamic>? actividad, {
    String? unidadId,
  }) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ActividadEditorPage(
          unidadId: unidadId ?? '${actividad?['unidadId'] ?? ''}',
          actividadActual: actividad,
        ),
      ),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _eliminarContenido(Map<String, dynamic> contenido) async {
    final confirmado = await confirmarEliminacion(
      context,
      'Eliminar contenido',
      '¿Eliminar «${contenido['titulo']}» del curso?',
    );
    if (!confirmado) return;
    try {
      await ref.read(repositorioAcademicoProvider).eliminarContenido('${contenido['id']}');
      await _cargar();
    } on ApiException catch (error) {
      _aviso(error.mensaje);
    }
  }

  Future<void> _eliminarActividad(Map<String, dynamic> actividad) async {
    final confirmado = await confirmarEliminacion(
      context,
      'Eliminar actividad',
      '¿Eliminar «${actividad['titulo']}»? No se puede deshacer.',
    );
    if (!confirmado) return;
    try {
      await ref.read(repositorioAcademicoProvider).eliminarActividad('${actividad['id']}');
      await _cargar();
    } on ApiException catch (error) {
      _aviso(error.mensaje);
    }
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
}
