import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Opción de respuesta en el editor de cuestionarios.
class _OpcionEd {
  _OpcionEd({this.texto = '', this.correcta = false}) : id = const Uuid().v4();
  final String id;
  String texto;
  bool correcta;
}

/// Pregunta del editor de cuestionarios.
class _PreguntaEd {
  _PreguntaEd({this.enunciado = ''}) : id = const Uuid().v4();
  final String id;
  String enunciado;
  final List<_OpcionEd> opciones = [_OpcionEd(), _OpcionEd()];
}

/// Editor de actividades en página completa (no ventana emergente).
///
/// Permite crear o editar tareas, foros y cuestionarios. En los cuestionarios se editan las
/// preguntas y sus respuestas correctas (corrección de la muestra) y se decide si el estudiante
/// puede revisar sus aciertos después de enviar. La fecha de cierre se elige con el calendario y
/// el reloj del sistema en una pantalla con desplazamiento, sin desbordes.
class ActividadEditorPage extends ConsumerStatefulWidget {
  const ActividadEditorPage({
    super.key,
    required this.unidadId,
    this.actividadActual,
    this.tipoInicial,
  });

  final String unidadId;
  final Map<String, dynamic>? actividadActual;
  final String? tipoInicial;

  @override
  ConsumerState<ActividadEditorPage> createState() => _ActividadEditorPageState();
}

class _ActividadEditorPageState extends ConsumerState<ActividadEditorPage> {
  final _titulo = TextEditingController();
  final _instrucciones = TextEditingController();
  final _peso = TextEditingController(text: '20');
  final _notaMaxima = TextEditingController(text: '5');
  final _formatos = TextEditingController();
  final _fecha = TextEditingController();
  final _hora = TextEditingController();

  String _tipo = 'TAREA';
  int _corte = 1;
  bool _revisionPermitida = false;
  final List<_PreguntaEd> _preguntas = [];
  final List<Map<String, dynamic>> _recursos = [];
  bool _subiendoRecurso = false;

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.actividadActual != null;

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoInicial ?? '${widget.actividadActual?['tipo'] ?? 'TAREA'}';
    _cargar();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _instrucciones.dispose();
    _peso.dispose();
    _notaMaxima.dispose();
    _formatos.dispose();
    _fecha.dispose();
    _hora.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final actual = widget.actividadActual;
    if (actual == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final datos = await ref
          .read(repositorioAcademicoProvider)
          .detalleEditorActividad('${actual['id']}');
      if (!mounted) return;
      setState(() {
        _tipo = '${datos['tipo']}';
        _titulo.text = '${datos['titulo'] ?? ''}';
        _instrucciones.text = '${datos['instrucciones'] ?? ''}';
        _peso.text = '${((datos['peso'] as num?) ?? 20).toStringAsFixed(0)}';
        _notaMaxima.text = '${((datos['notaMaxima'] as num?) ?? 5).toStringAsFixed(0)}';
        _corte = (datos['corte'] as num?)?.toInt() ?? 1;
        final cierre = DateTime.tryParse('${datos['cierraEn']}')?.toLocal();
        _fecha.text = cierre == null
            ? ''
            : '${cierre.year.toString().padLeft(4, '0')}-${cierre.month.toString().padLeft(2, '0')}-${cierre.day.toString().padLeft(2, '0')}';
        _hora.text = cierre == null
            ? ''
            : '${cierre.hour.toString().padLeft(2, '0')}:${cierre.minute.toString().padLeft(2, '0')}';
        _revisionPermitida = datos['revisionPermitida'] == true;
        _formatos.text =
            ((datos['formatosPermitidos'] as List<dynamic>?) ?? const []).map((f) => '$f').join(', ');
        _recursos
          ..clear()
          ..addAll(
            ((datos['recursos'] as List<dynamic>?) ?? const [])
                .whereType<Map>()
                .map((recurso) => Map<String, dynamic>.from(recurso)),
          );
        _preguntas
          ..clear()
          ..addAll(
            ((datos['preguntas'] as List<dynamic>?) ?? const []).whereType<Map>().map((fila) {
              final pregunta = _PreguntaEd(enunciado: '${fila['enunciado'] ?? ''}');
              pregunta.opciones.clear();
              for (final opcion in ((fila['opciones'] as List<dynamic>?) ?? const []).whereType<Map>()) {
                pregunta.opciones.add(_OpcionEd(
                  texto: '${opcion['texto'] ?? ''}',
                  correcta: opcion['esCorrecta'] == true,
                ));
              }
              if (pregunta.opciones.length < 2) {
                pregunta.opciones.add(_OpcionEd());
              }
              return pregunta;
            }),
          );
        if (_tipo == 'CUESTIONARIO' && _preguntas.isEmpty) {
          _preguntas.add(_PreguntaEd());
        }
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.mensaje;
          _cargando = false;
        });
      }
    }
  }

  /// Lee fecha/hora escritas a mano (24 h). Devuelve `null` si se dejaron vacías.
  DateTime? _parseCierre() {
    final fecha = _fecha.text.trim();
    final hora = _hora.text.trim();
    if (fecha.isEmpty && hora.isEmpty) return null;
    final regexFecha = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final regexHora = RegExp(r'^(\d{1,2}):(\d{2})$');
    final coincidenciaFecha = regexFecha.firstMatch(fecha);
    final coincidenciaHora = regexHora.firstMatch(hora);
    if (coincidenciaFecha == null || coincidenciaHora == null) return null;
    final anio = int.parse(coincidenciaFecha.group(1)!);
    final mes = int.parse(coincidenciaFecha.group(2)!);
    final dia = int.parse(coincidenciaFecha.group(3)!);
    final horas = int.parse(coincidenciaHora.group(1)!);
    final minutos = int.parse(coincidenciaHora.group(2)!);
    if (horas > 23 || minutos > 59) return null;
    final fechaHora = DateTime(anio, mes, dia, horas, minutos);
    if (fechaHora.year != anio || fechaHora.month != mes || fechaHora.day != dia) return null;
    return fechaHora;
  }

  Future<void> _adjuntarRecurso() async {
    setState(() {
      _subiendoRecurso = true;
      _error = null;
    });
    try {
      final archivo = await openFile();
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (bytes.length > 50 * 1024 * 1024) {
        setState(() => _error = 'El archivo supera el máximo de 50 MB.');
        return;
      }
      final mime = archivo.mimeType ?? 'application/octet-stream';
      final firma = await ref.read(repositorioAcademicoProvider).subirArchivo(
            contexto: 'CONTENIDO',
            nombre: archivo.name,
            mime: mime,
            bytes: bytes,
          );
      if (!mounted) return;
      setState(() {
        _recursos.add({
          'objetoKey': '${firma['objetoKey']}',
          'nombre': archivo.name,
          'mime': mime,
          'tamano': bytes.length,
        });
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = 'No se pudo adjuntar el archivo: ${error.mensaje}');
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo adjuntar el archivo al datalake.');
    } finally {
      if (mounted) setState(() => _subiendoRecurso = false);
    }
  }

  Future<void> _quitarRecurso(Map<String, dynamic> recurso) async {
    final recursoId = recurso['id'];
    if (recursoId != null) {
      try {
        await ref.read(repositorioAcademicoProvider).eliminarRecursoActividad('$recursoId');
      } on ApiException catch (error) {
        if (mounted) setState(() => _error = error.mensaje);
        return;
      }
    }
    if (mounted) setState(() => _recursos.remove(recurso));
  }

  List<String> get _formatosLista => _formatos.text
      .split(',')
      .map((formato) => formato.trim().toLowerCase().replaceAll('.', ''))
      .where((formato) => formato.isNotEmpty)
      .toList();

  Future<void> _guardar() async {
    final titulo = _titulo.text.trim();
    if (titulo.length < 3) {
      setState(() => _error = 'Escribe un título de al menos 3 caracteres.');
      return;
    }
    final peso = double.tryParse(_peso.text.trim().replaceAll(',', '.'));
    if (peso == null || peso <= 0 || peso > 100) {
      setState(() => _error = 'El peso debe estar entre 1 y 100.');
      return;
    }
    final cierraEn = _parseCierre();
    if ((_fecha.text.trim().isNotEmpty || _hora.text.trim().isNotEmpty) && cierraEn == null) {
      setState(() => _error =
          'Fecha u hora inválidas. Usa AAAA-MM-DD y HH:MM en formato 24 h (por ejemplo 2026-12-31 y 13:30).');
      return;
    }
    if (_tipo == 'CUESTIONARIO') {
      if (_preguntas.isEmpty) {
        setState(() => _error = 'Agrega al menos una pregunta.');
        return;
      }
      for (final pregunta in _preguntas) {
        if (pregunta.enunciado.trim().length < 3) {
          setState(() => _error = 'Cada pregunta necesita un enunciado.');
          return;
        }
        if (pregunta.opciones.length < 2 || !pregunta.opciones.any((opcion) => opcion.correcta)) {
          setState(() => _error = 'Cada pregunta necesita al menos 2 opciones y una correcta.');
          return;
        }
        if (pregunta.opciones.any((opcion) => opcion.texto.trim().isEmpty)) {
          setState(() => _error = 'Ninguna opción puede quedar vacía.');
          return;
        }
      }
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositorioAcademicoProvider);
      final formatos = _tipo == 'TAREA' ? _formatosLista : <String>[];
      String actividadId;
      if (_editando) {
        actividadId = '${widget.actividadActual!['id']}';
        await repo.editarActividad(
          actividadId,
          titulo: titulo,
          instrucciones: _instrucciones.text.trim(),
          cierraEn: cierraEn,
          peso: peso,
          formatosPermitidos: formatos,
          revisionPermitida: _tipo == 'CUESTIONARIO' ? _revisionPermitida : null,
        );
      } else {
        final creada = await repo.crearActividad(
          widget.unidadId,
          tipo: _tipo,
          titulo: titulo,
          instrucciones: _instrucciones.text.trim().isEmpty ? null : _instrucciones.text.trim(),
          cierraEn: cierraEn,
          corte: _corte,
          peso: peso,
          formatosPermitidos: formatos.isEmpty ? null : formatos,
          revisionPermitida: _tipo == 'CUESTIONARIO' ? _revisionPermitida : null,
        );
        actividadId = '${creada['id']}';
      }

      if (_tipo == 'CUESTIONARIO') {
        await repo.reemplazarCuestionario(
          actividadId,
          revisionPermitida: _revisionPermitida,
          preguntas: [
            for (final pregunta in _preguntas)
              {
                'enunciado': pregunta.enunciado.trim(),
                'tipo': 'UNICA',
                'opciones': [
                  for (final opcion in pregunta.opciones)
                    {'texto': opcion.texto.trim(), 'esCorrecta': opcion.correcta},
                ],
              },
          ],
        );
      }

      // Archivos/materiales nuevos de la actividad (los que ya existían se conservan y los
      // eliminados se borraron al pulsar la X).
      for (final recurso in _recursos.where((recurso) => recurso['id'] == null)) {
        await repo.agregarRecursoActividad(
          actividadId,
          objetoKey: '${recurso['objetoKey']}',
          nombre: '${recurso['nombre']}',
          mime: recurso['mime'] as String?,
          tamano: (recurso['tamano'] as num?)?.toInt(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar la actividad.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar actividad' : 'Nueva actividad'),
        actions: [
          TextButton(
            onPressed: _guardando ? null : _guardar,
            child: Text(_guardando ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Tipo de actividad', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'TAREA', icon: Icon(Icons.assignment_outlined), label: Text('Tarea')),
                    ButtonSegment(value: 'CUESTIONARIO', icon: Icon(Icons.quiz_outlined), label: Text('Cuestionario')),
                    ButtonSegment(value: 'FORO', icon: Icon(Icons.forum_outlined), label: Text('Foro')),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: _editando
                      ? null
                      : (seleccion) => setState(() {
                            _tipo = seleccion.first;
                            if (_tipo == 'CUESTIONARIO' && _preguntas.isEmpty) {
                              _preguntas.add(_PreguntaEd());
                            }
                          }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titulo,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _instrucciones,
                  minLines: 4,
                  maxLines: 12,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Instrucciones / descripción',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _corte,
                        decoration: const InputDecoration(labelText: 'Corte', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Corte 1')),
                          DropdownMenuItem(value: 2, child: Text('Corte 2')),
                          DropdownMenuItem(value: 3, child: Text('Corte 3')),
                        ],
                        onChanged: (valor) => setState(() => _corte = valor ?? 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _peso,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Peso %', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Cierre de la actividad (opcional)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fecha,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Fecha (AAAA-MM-DD)',
                          hintText: '2026-12-31',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _hora,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Hora 24 h (HH:MM)',
                          hintText: '13:30',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Hora militar: 08:00, 13:30, 18:45. Se escribe a mano; si no hay cierre, deja ambos campos vacíos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Archivos de la actividad', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        const Text(
                          'Puedes adjuntar material propio de esta tarea, examen o foro (PDF, imágenes, '
                          'PowerPoint, Excel, etc.). El estudiante lo verá al abrir la actividad.',
                        ),
                        if (_recursos.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final recurso in _recursos)
                                InputChip(
                                  avatar: const Icon(Icons.insert_drive_file, size: 16),
                                  label: Text('${recurso['nombre']}'),
                                  onDeleted: () => _quitarRecurso(recurso),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _subiendoRecurso ? null : _adjuntarRecurso,
                          icon: _subiendoRecurso
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.attach_file),
                          label: Text(_subiendoRecurso ? 'Subiendo…' : 'Adjuntar archivo a la actividad'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_tipo == 'TAREA') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _formatos,
                    decoration: const InputDecoration(
                      labelText: 'Formatos permitidos (separados por coma)',
                      hintText: 'pdf, docx, png',
                      helperText: 'Si se deja vacío se acepta cualquier archivo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_tipo == 'CUESTIONARIO') ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _revisionPermitida,
                    onChanged: (valor) => setState(() => _revisionPermitida = valor),
                    title: const Text('Permitir revisión después de enviar'),
                    subtitle: const Text('El estudiante verá qué respuestas acertó'),
                  ),
                  const SizedBox(height: 8),
                  Text('Preguntas', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final (indice, pregunta) in _preguntas.indexed)
                    _tarjetaPregunta(context, indice, pregunta),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _preguntas.add(_PreguntaEd())),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir pregunta'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colores.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: TextStyle(color: colores.onErrorContainer)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar actividad'),
                ),
              ],
            ),
    );
  }

  Widget _tarjetaPregunta(BuildContext context, int indice, _PreguntaEd pregunta) {
    return Card(
      key: ValueKey(pregunta.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Pregunta ${indice + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: 'Quitar pregunta',
                  onPressed: _preguntas.length == 1
                      ? null
                      : () => setState(() => _preguntas.remove(pregunta)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              key: ValueKey('enunciado-${pregunta.id}'),
              initialValue: pregunta.enunciado,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Enunciado',
                border: OutlineInputBorder(),
              ),
              onChanged: (valor) => pregunta.enunciado = valor,
            ),
            const SizedBox(height: 8),
            for (final (posicion, opcion) in pregunta.opciones.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Respuesta correcta',
                      onPressed: () => setState(() {
                        for (final otra in pregunta.opciones) {
                          otra.correcta = false;
                        }
                        opcion.correcta = true;
                      }),
                      icon: Icon(
                        opcion.correcta ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: opcion.correcta ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('opcion-${opcion.id}'),
                        initialValue: opcion.texto,
                        decoration: InputDecoration(
                          labelText: 'Opción ${posicion + 1}',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (valor) => opcion.texto = valor,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar opción',
                      onPressed: pregunta.opciones.length <= 2
                          ? null
                          : () => setState(() => pregunta.opciones.remove(opcion)),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: pregunta.opciones.length >= 6
                    ? null
                    : () => setState(() => pregunta.opciones.add(_OpcionEd())),
                icon: const Icon(Icons.add),
                label: const Text('Añadir opción'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
