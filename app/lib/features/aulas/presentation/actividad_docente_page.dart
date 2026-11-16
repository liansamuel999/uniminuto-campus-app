import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import 'actividad_editor_page.dart';
import 'foro_page.dart';

/// Actividad vista por el docente: datos, entregas/adjuntos, intentos y calificación.
class ActividadDocentePage extends ConsumerStatefulWidget {
  const ActividadDocentePage({
    super.key,
    required this.actividad,
    required this.aulaId,
    this.docenteNombre = '',
  });

  final Map<String, dynamic> actividad;
  final String aulaId;
  final String docenteNombre;

  @override
  ConsumerState<ActividadDocentePage> createState() => _ActividadDocentePageState();
}

class _ActividadDocentePageState extends ConsumerState<ActividadDocentePage> {
  List<Map<String, dynamic>> _calificaciones = const [];
  List<Map<String, dynamic>> _entregas = const [];
  List<Map<String, dynamic>> _intentos = const [];
  Map<String, dynamic> _detalle = const {};
  bool _cargando = true;
  String? _error;

  String get _tipo => '${_detalle['tipo'] ?? widget.actividad['tipo']}';

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
      final actividadId = '${widget.actividad['id']}';
      final calificaciones = await api.getList('/aulas/${widget.aulaId}/calificaciones');
      final entregas = _tipo == 'TAREA'
          ? await api.getList('/actividades/$actividadId/entregas')
          : <dynamic>[];
      final intentos = _tipo == 'CUESTIONARIO'
          ? await api.getList('/cuestionarios/$actividadId/intentos')
          : <dynamic>[];
      Map<String, dynamic> detalle = const {};
      try {
        detalle = await api.getJson('/actividades/$actividadId/editor');
      } on ApiException {
        // Si el usuario no es el docente dueño (p. ej. admin), se usa la actividad del aula.
      }
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _calificaciones = _mapas(calificaciones)
            .where((fila) => '${fila['actividadId']}' == actividadId)
            .toList();
        _entregas = _mapas(entregas);
        _intentos = _mapas(intentos);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static List<Map<String, dynamic>> _mapas(List<dynamic> datos) =>
      datos.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final actividad = <String, dynamic>{...widget.actividad, ..._detalle};
    final cierra = DateTime.tryParse('${actividad['cierraEn']}');

    return Scaffold(
      appBar: AppBar(
        title: Text('${actividad['titulo']}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Editar actividad',
            onPressed: () async {
              final guardado = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => ActividadEditorPage(
                    unidadId: '',
                    actividadActual: actividad,
                  ),
                ),
              );
              if (guardado == true) await _cargar();
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Chip(label: Text(_tipo), visualDensity: VisualDensity.compact),
                        const SizedBox(width: 8),
                        Text('${actividad['peso']}% · corte ${actividad['corte']}'),
                        const Spacer(),
                        if (cierra != null) Text('Cierra ${fechaHoraCorta(cierra)}'),
                      ],
                    ),
                    if (('${actividad['instrucciones'] ?? ''}').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('${actividad['instrucciones']}'),
                    ],
                    if (((actividad['recursos'] as List<dynamic>?) ?? const []).whereType<Map>().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Materiales de la actividad', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final recurso in (actividad['recursos'] as List<dynamic>).whereType<Map>())
                            ActionChip(
                              avatar: const Icon(Icons.attach_file, size: 16),
                              label: Text('${recurso['nombre'] ?? 'archivo'}'),
                              onPressed: () => _abrirAdjunto(
                                context,
                                Map<String, dynamic>.from(recurso),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (_tipo == 'FORO') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ForoPage(
                              foroId: '${actividad['id']}',
                              aulaId: widget.aulaId,
                              titulo: '${actividad['titulo']}',
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Abrir foro'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
            if (_tipo == 'TAREA') ...[
              const SizedBox(height: 16),
              Text('Entregas (${_entregas.length})', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_entregas.isEmpty) const Text('Ningún estudiante ha entregado todavía.'),
              for (final entrega in _entregas) _tarjetaEntrega(context, entrega),
            ],
            if (_tipo == 'CUESTIONARIO') ...[
              const SizedBox(height: 16),
              Text('Intentos (${_intentos.length})', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_intentos.isEmpty) const Text('Ningún estudiante ha respondido todavía.'),
              for (final intento in _intentos)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${intento['puntaje']}')),
                    title: Text('${intento['estudiante']}'),
                    subtitle: Text('Enviado ${fechaHoraCorta(DateTime.tryParse('${intento['enviadoEn']}'))}'),
                    trailing: TextButton(
                      onPressed: () => _verIntento(intento),
                      child: const Text('Ver respuestas'),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text('Calificar estudiantes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (!_cargando && _calificaciones.isEmpty) const Text('Sin estudiantes en el curso.'),
            for (final fila in _calificaciones)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('${fila['estudiante']}'),
                  subtitle: Text(
                    fila['nota'] == null ? 'Sin calificar' : 'Nota ${fila['nota']} / ${fila['notaMaxima']}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Calificar',
                    onPressed: () => _calificar(fila),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaEntrega(BuildContext context, Map<String, dynamic> entrega) {
    final adjuntos = (entrega['adjuntos'] as List<dynamic>? ?? const []);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          '${entrega['estado']}' == 'TARDIA' ? Icons.warning_amber_outlined : Icons.check_circle_outline,
        ),
        title: Text('${entrega['estudiante']}'),
        subtitle: Text(
          '${entrega['estado']} · ${fechaHoraCorta(DateTime.tryParse('${entrega['recibidaEnServidor']}'))}'
          '${entrega['nota'] == null ? '' : ' · nota ${entrega['nota']}'}',
        ),
        children: [
          if (('${entrega['texto'] ?? ''}').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${entrega['texto']}'),
              ),
            ),
          if (adjuntos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final adjunto in adjuntos.whereType<Map>())
                    ActionChip(
                      avatar: const Icon(Icons.attach_file, size: 16),
                      label: Text('${adjunto['nombre'] ?? 'adjunto'}'),
                      onPressed: () => _abrirAdjunto(context, Map<String, dynamic>.from(adjunto)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirAdjunto(BuildContext context, Map<String, dynamic> adjunto) async {
    final objetoKey = adjunto['objetoKey'];
    if (objetoKey == null) return;
    try {
      final url = await ref.read(repositorioAcademicoProvider).urlDeObjeto('$objetoKey');
      if (!context.mounted) return;
      await abrirEnlace(context, url);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  void _verIntento(Map<String, dynamic> intento) {
    final detalle = (intento['detalle'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((fila) => Map<String, dynamic>.from(fila))
        .toList();
    showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('Respuestas de ${intento['estudiante']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Puntaje: ${intento['puntaje']}'),
              const SizedBox(height: 8),
              if (detalle.isEmpty) const Text('Sin detalle de respuestas.'),
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
                              color: respuesta['acerto'] == true
                                  ? Colors.green
                                  : Theme.of(contexto).colorScheme.error,
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
                        const SizedBox(height: 6),
                        for (final opcion in ((respuesta['opciones'] as List<dynamic>?) ?? const [])
                            .whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${((respuesta['elegidas'] as List<dynamic>?) ?? const []).contains('${opcion['id']}') ? '✔ Elegida' : '   '} '
                              '${opcion['texto']} ${opcion['esCorrecta'] == true ? '(correcta)' : ''}',
                              style: TextStyle(
                                color: opcion['esCorrecta'] == true
                                    ? Colors.green
                                    : (((respuesta['elegidas'] as List<dynamic>?) ?? const [])
                                            .contains('${opcion['id']}'))
                                        ? Theme.of(contexto).colorScheme.error
                                        : null,
                              ),
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
  }

  Future<void> _calificar(Map<String, dynamic> fila) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoNota(
        estudiante: '${fila['estudiante']}',
        notaMaxima: (fila['notaMaxima'] as num?)?.toDouble() ?? 5,
        notaActual: (fila['nota'] as num?)?.toDouble(),
        retroActual: fila['retroalimentacion'] as String?,
      ),
    );
    if (resultado == null) return;
    try {
      await ref.read(apiClientProvider).putJson('/calificaciones', cuerpo: {
        'actividadId': '${widget.actividad['id']}',
        'inscripcionId': '${fila['inscripcionId']}',
        'nota': resultado['nota'],
        if (resultado['retroalimentacion'] != null) 'retroalimentacion': resultado['retroalimentacion'],
      });
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }
}

class _DialogoNota extends StatefulWidget {
  const _DialogoNota({
    required this.estudiante,
    required this.notaMaxima,
    this.notaActual,
    this.retroActual,
  });

  final String estudiante;
  final double notaMaxima;
  final double? notaActual;
  final String? retroActual;

  @override
  State<_DialogoNota> createState() => _DialogoNotaState();
}

class _DialogoNotaState extends State<_DialogoNota> {
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
          children: [
            TextField(
              controller: _nota,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Nota (0 – ${widget.notaMaxima})'),
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
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar nota')),
      ],
    );
  }
}
