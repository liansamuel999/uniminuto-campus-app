import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import 'analitica_tab.dart';
import 'planificacion_tab.dart';

/// Panel del Admin Académico: periodos, asignaturas, cursos, inscripciones y horarios/salones.
class AdminAcademicoPage extends ConsumerWidget {
  const AdminAcademicoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración académica'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Periodos'),
              Tab(text: 'Asignaturas'),
              Tab(text: 'Cursos'),
              Tab(text: 'Inscripciones'),
              Tab(text: 'Horarios y salones'),
              Tab(text: 'Analítica'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PeriodosTab(),
            _AsignaturasTab(),
            _GruposTab(),
            _InscripcionesTab(),
            PlanificacionTab(),
            AnaliticaTab(),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _aMapas(List<dynamic> datos) =>
    datos.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();

void _aviso(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}

class _ErrorTexto extends StatelessWidget {
  const _ErrorTexto(this.mensaje);

  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    if (mensaje == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(mensaje!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

// ─────────────────────────────── Periodos ────────────────────────────────────
class _PeriodosTab extends ConsumerStatefulWidget {
  const _PeriodosTab();

  @override
  ConsumerState<_PeriodosTab> createState() => _PeriodosTabState();
}

class _PeriodosTabState extends ConsumerState<_PeriodosTab> {
  List<Map<String, dynamic>> _periodos = const [];
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
      final datos = await ref.read(repositorioAdminProvider).periodos();
      if (mounted) setState(() => _periodos = _aMapas(datos));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editar([Map<String, dynamic>? actual]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _DialogoPeriodo(actual: actual),
    );
    if (datos == null) return;
    try {
      final repo = ref.read(repositorioAdminProvider);
      if (actual == null) {
        await repo.crearPeriodo(datos);
      } else {
        await repo.actualizarPeriodo('${actual['id']}', datos);
      }
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> periodo) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Eliminar periodo'),
        content: Text('¿Eliminar el periodo ${periodo['codigo']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(contexto).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await ref.read(repositorioAdminProvider).eliminarPeriodo('${periodo['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Periodo'),
      ),
      body: ListView(
        // Espacio inferior para que el botón flotante «crear» no tape el menú de acciones
        // (tres puntos) del último elemento de la lista.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          _ErrorTexto(_error),
          if (!_cargando && _periodos.isEmpty) const Text('No hay periodos registrados.'),
          for (final periodo in _periodos)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text('${periodo['codigo']} · ${periodo['tipo']}'),
                subtitle: Text('${periodo['fechaInicio']} → ${periodo['fechaFin']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (periodo['activo'] == true)
                      const Chip(label: Text('Activo'), visualDensity: VisualDensity.compact)
                    else
                      const SizedBox.shrink(),
                    PopupMenuButton<String>(
                      onSelected: (valor) => valor == 'editar' ? _editar(periodo) : _eliminar(periodo),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogoPeriodo extends StatefulWidget {
  const _DialogoPeriodo({this.actual});

  final Map<String, dynamic>? actual;

  @override
  State<_DialogoPeriodo> createState() => _DialogoPeriodoState();
}

class _DialogoPeriodoState extends State<_DialogoPeriodo> {
  late final TextEditingController _codigo = TextEditingController(text: '${widget.actual?['codigo'] ?? ''}');
  late final TextEditingController _inicio = TextEditingController(text: '${widget.actual?['fechaInicio'] ?? ''}');
  late final TextEditingController _fin = TextEditingController(text: '${widget.actual?['fechaFin'] ?? ''}');
  late String _tipo = '${widget.actual?['tipo'] ?? 'SEMESTRAL'}';
  late bool _activo = widget.actual?['activo'] == true;

  @override
  void dispose() {
    _codigo.dispose();
    _inicio.dispose();
    _fin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.actual == null ? 'Nuevo periodo' : 'Editar periodo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _codigo, decoration: const InputDecoration(labelText: 'Código (AAAA-N)')),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'SEMESTRAL', child: Text('Semestral')),
                DropdownMenuItem(value: 'CUATRIMESTRAL', child: Text('Cuatrimestral')),
              ],
              onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
            ),
            TextField(controller: _inicio, decoration: const InputDecoration(labelText: 'Inicio (AAAA-MM-DD)')),
            TextField(controller: _fin, decoration: const InputDecoration(labelText: 'Fin (AAAA-MM-DD)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _activo,
              onChanged: (valor) => setState(() => _activo = valor),
              title: const Text('Periodo activo'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'codigo': _codigo.text.trim(),
            'tipo': _tipo,
            'fechaInicio': _inicio.text.trim(),
            'fechaFin': _fin.text.trim(),
            'activo': _activo,
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ────────────────────────────── Asignaturas ─────────────────────────────────
class _AsignaturasTab extends ConsumerStatefulWidget {
  const _AsignaturasTab();

  @override
  ConsumerState<_AsignaturasTab> createState() => _AsignaturasTabState();
}

class _AsignaturasTabState extends ConsumerState<_AsignaturasTab> {
  List<Map<String, dynamic>> _asignaturas = const [];
  List<Map<String, dynamic>> _programas = const [];
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
      final repo = ref.read(repositorioAdminProvider);
      final resultados = await Future.wait([repo.asignaturas(), repo.programas()]);
      if (mounted) {
        setState(() {
          _asignaturas = _aMapas(resultados[0]);
          _programas = _aMapas(resultados[1]);
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editar([Map<String, dynamic>? actual]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _DialogoAsignatura(actual: actual, programas: _programas),
    );
    if (datos == null) return;
    try {
      final repo = ref.read(repositorioAdminProvider);
      if (actual == null) {
        await repo.crearAsignatura(datos);
      } else {
        await repo.actualizarAsignatura('${actual['id']}', datos);
      }
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> asignatura) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarAsignatura('${asignatura['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Asignatura'),
      ),
      body: ListView(
        // Espacio inferior para que el botón flotante «crear» no tape el menú de acciones
        // (tres puntos) del último elemento de la lista.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          _ErrorTexto(_error),
          for (final asignatura in _asignaturas)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text('${asignatura['nombre']}'),
                subtitle: Text(
                  '${asignatura['codigo']} · ${asignatura['creditos']} créditos · '
                  'Semestre ${asignatura['semestre'] ?? 1}'
                  '${asignatura['programa'] == null ? '' : ' · ${asignatura['programa']}'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (valor) => valor == 'editar' ? _editar(asignatura) : _eliminar(asignatura),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogoAsignatura extends StatefulWidget {
  const _DialogoAsignatura({this.actual, required this.programas});

  final Map<String, dynamic>? actual;
  final List<Map<String, dynamic>> programas;

  @override
  State<_DialogoAsignatura> createState() => _DialogoAsignaturaState();
}

class _DialogoAsignaturaState extends State<_DialogoAsignatura> {
  late final TextEditingController _codigo = TextEditingController(text: '${widget.actual?['codigo'] ?? ''}');
  late final TextEditingController _nombre = TextEditingController(text: '${widget.actual?['nombre'] ?? ''}');
  late final TextEditingController _creditos = TextEditingController(text: '${widget.actual?['creditos'] ?? 3}');
  late final TextEditingController _semestre = TextEditingController(text: '${widget.actual?['semestre'] ?? 1}');
  String? _programaId;

  @override
  void initState() {
    super.initState();
    _programaId = widget.actual?['programaId'] as String?;
    if (_programaId == null && widget.programas.isNotEmpty) {
      _programaId = '${widget.programas.first['id']}';
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _creditos.dispose();
    _semestre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.actual == null ? 'Nueva asignatura' : 'Editar asignatura'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _codigo, decoration: const InputDecoration(labelText: 'Código')),
            TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(
              controller: _creditos,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Créditos'),
            ),
            TextField(
              controller: _semestre,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Semestre'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _programaId,
              decoration: const InputDecoration(labelText: 'Programa académico'),
              items: [
                for (final programa in widget.programas)
                  DropdownMenuItem(value: '${programa['id']}', child: Text('${programa['nombre']}')),
              ],
              onChanged: (valor) => setState(() => _programaId = valor),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'codigo': _codigo.text.trim(),
            'nombre': _nombre.text.trim(),
            'creditos': int.tryParse(_creditos.text.trim()) ?? 0,
            'semestre': int.tryParse(_semestre.text.trim()) ?? 1,
            'programaId': _programaId,
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ───────────────────────────────── Cursos ────────────────────────────────────
class _GruposTab extends ConsumerStatefulWidget {
  const _GruposTab();

  @override
  ConsumerState<_GruposTab> createState() => _GruposTabState();
}

class _GruposTabState extends ConsumerState<_GruposTab> {
  List<Map<String, dynamic>> _grupos = const [];
  List<Map<String, dynamic>> _asignaturas = const [];
  List<Map<String, dynamic>> _periodos = const [];
  List<Map<String, dynamic>> _docentes = const [];
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
      final repo = ref.read(repositorioAdminProvider);
      final resultados = await Future.wait([
        repo.grupos(),
        repo.asignaturas(),
        repo.periodos(),
        repo.usuarios('DOCENTE'),
      ]);
      if (!mounted) return;
      setState(() {
        _grupos = _aMapas(resultados[0]);
        _asignaturas = _aMapas(resultados[1]);
        _periodos = _aMapas(resultados[2]);
        _docentes = _aMapas(resultados[3]);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _DialogoGrupo(asignaturas: _asignaturas, periodos: _periodos),
    );
    if (datos == null) return;
    try {
      await ref.read(repositorioAdminProvider).crearGrupo(datos);
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _asignar(Map<String, dynamic> grupo) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _DialogoAsignacion(grupo: grupo, docentes: _docentes),
    );
    if (datos == null) return;
    try {
      await ref.read(repositorioAdminProvider).actualizarGrupo('${grupo['id']}', datos);
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> grupo) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarGrupo('${grupo['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _generarHorario(Map<String, dynamic> grupo) async {
    try {
      final horarios = await ref.read(repositorioAdminProvider).generarHorarioGrupo('${grupo['id']}');
      await _cargar();
      if (mounted) {
        _aviso(
          context,
          horarios.isEmpty
              ? 'No se generaron franjas.'
              : 'Horario generado: ${horarios.length} franja(s) con día y salón.',
        );
      }
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _asignaturas.isEmpty || _periodos.isEmpty ? null : _crear,
        icon: const Icon(Icons.add),
        label: const Text('Curso'),
      ),
      body: ListView(
        // Espacio inferior para que el botón flotante «crear» no tape el menú de acciones
        // (tres puntos) del último elemento de la lista.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          _ErrorTexto(_error),
          for (final grupo in _grupos)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text('${grupo['asignatura']} · Curso ${grupo['codigoCurso']}'),
                subtitle: Text(
                  '${grupo['codigoAsignatura']} · ${grupo['periodo']} · '
                  'Semestre ${grupo['semestre'] ?? 1} · '
                  '${grupo['programa'] ?? 'Sin programa'} · '
                  '${grupo['docente'] ?? 'Sin docente'} · ${grupo['estudiantes']} estudiantes',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (valor) {
                    if (valor == 'asignar') _asignar(grupo);
                    if (valor == 'generar') _generarHorario(grupo);
                    if (valor == 'eliminar') _eliminar(grupo);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'asignar', child: Text('Editar / asignar docente')),
                    PopupMenuItem(value: 'generar', child: Text('Generar días y salones')),
                    PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogoGrupo extends StatefulWidget {
  const _DialogoGrupo({required this.asignaturas, required this.periodos});

  final List<Map<String, dynamic>> asignaturas;
  final List<Map<String, dynamic>> periodos;

  @override
  State<_DialogoGrupo> createState() => _DialogoGrupoState();
}

class _DialogoGrupoState extends State<_DialogoGrupo> {
  String? _asignaturaId;
  String? _periodoId;
  final _codigo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _asignaturaId = widget.asignaturas.isEmpty ? null : '${widget.asignaturas.first['id']}';
    _periodoId = widget.periodos.isEmpty ? null : '${widget.periodos.first['id']}';
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo curso'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _asignaturaId,
              decoration: const InputDecoration(labelText: 'Asignatura'),
              items: [
                for (final asignatura in widget.asignaturas)
                  DropdownMenuItem(value: '${asignatura['id']}', child: Text('${asignatura['nombre']}')),
              ],
              onChanged: (valor) => setState(() => _asignaturaId = valor),
            ),
            DropdownButtonFormField<String>(
              initialValue: _periodoId,
              decoration: const InputDecoration(labelText: 'Periodo'),
              items: [
                for (final periodo in widget.periodos)
                  DropdownMenuItem(value: '${periodo['id']}', child: Text('${periodo['codigo']}')),
              ],
              onChanged: (valor) => setState(() => _periodoId = valor),
            ),
            TextField(
              controller: _codigo,
              decoration: const InputDecoration(
                labelText: 'Código único del curso',
                hintText: 'Ej.: 1234 o IS201-2026-01',
                helperText: 'Dos cursos de la misma materia se distinguen por este código',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'asignaturaId': _asignaturaId,
            'periodoId': _periodoId,
            'codigoCurso': _codigo.text.trim(),
          }),
          child: const Text('Crear curso'),
        ),
      ],
    );
  }
}

class _DialogoAsignacion extends StatefulWidget {
  const _DialogoAsignacion({required this.grupo, required this.docentes});

  final Map<String, dynamic> grupo;
  final List<Map<String, dynamic>> docentes;

  @override
  State<_DialogoAsignacion> createState() => _DialogoAsignacionState();
}

class _DialogoAsignacionState extends State<_DialogoAsignacion> {
  String? _docenteId;

  @override
  void initState() {
    super.initState();
    _docenteId = widget.grupo['docenteId'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.grupo['asignatura']} · Curso ${widget.grupo['codigoCurso']}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _docenteId,
              decoration: const InputDecoration(labelText: 'Docente'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sin docente')),
                for (final docente in widget.docentes)
                  DropdownMenuItem<String?>(
                    value: '${docente['id']}',
                    child: Text('${docente['nombres']} ${docente['apellidos']}'),
                  ),
              ],
              onChanged: (valor) => setState(() => _docenteId = valor),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({'docenteId': _docenteId}),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────── Inscripciones ──────────────────────────────
class _InscripcionesTab extends ConsumerStatefulWidget {
  const _InscripcionesTab();

  @override
  ConsumerState<_InscripcionesTab> createState() => _InscripcionesTabState();
}

class _InscripcionesTabState extends ConsumerState<_InscripcionesTab> {
  List<Map<String, dynamic>> _grupos = const [];
  List<Map<String, dynamic>> _estudiantes = const [];
  List<Map<String, dynamic>> _inscripciones = const [];
  String? _grupoId;
  String? _programaFiltro;
  int? _semestreFiltro;
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
      final repo = ref.read(repositorioAdminProvider);
      final grupos = await repo.grupos();
      final estudiantes = await repo.usuarios('ESTUDIANTE');
      final lista = _aMapas(grupos);
      String? programa = _programaFiltro;
      if (programa == null && lista.isNotEmpty) {
        programa = '${lista.firstWhere((g) => g['programaId'] != null, orElse: () => lista.first)['programaId']}';
      }
      int? semestre = _semestreFiltro;
      if (semestre == null && lista.isNotEmpty) {
        semestre = int.tryParse('${lista.first['semestre'] ?? 1}') ?? 1;
      }
      final filtrados = lista.where((grupo) {
        if (programa != null && '${grupo['programaId'] ?? ''}' != programa) return false;
        if (semestre != null && '${grupo['semestre'] ?? 1}' != '$semestre') return false;
        return true;
      }).toList();
      final seleccionado = _grupoId != null && filtrados.any((g) => '${g['id']}' == _grupoId)
          ? _grupoId
          : (filtrados.isEmpty ? null : '${filtrados.first['id']}');
      final inscripciones = seleccionado == null
          ? <dynamic>[]
          : await repo.inscripciones(grupoId: seleccionado);
      if (!mounted) return;
      setState(() {
        _grupos = lista;
        _estudiantes = _aMapas(estudiantes);
        _programaFiltro = programa;
        _semestreFiltro = semestre;
        _grupoId = seleccionado;
        _inscripciones = _aMapas(inscripciones);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarGrupo(String? id) async {
    if (id == null) return;
    setState(() {
      _grupoId = id;
      _cargando = true;
    });
    try {
      final datos = await ref.read(repositorioAdminProvider).inscripciones(grupoId: id);
      if (!mounted) return;
      setState(() => _inscripciones = _aMapas(datos));
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crear() async {
    if (_grupoId == null) return;
    final estudiantes = _estudiantesFiltrados;
    if (estudiantes.isEmpty) {
      _aviso(context, 'No hay estudiantes del programa de este curso para inscribir.');
      return;
    }
    final estudianteId = await showDialog<String>(
      context: context,
      builder: (contexto) => SimpleDialog(
        title: const Text('Inscribir estudiante del programa'),
        children: [
          for (final estudiante in estudiantes)
            SimpleDialogOption(
              onPressed: () => Navigator.of(contexto).pop('${estudiante['id']}'),
              child: Text(
                '${estudiante['nombres']} ${estudiante['apellidos']}'
                '${estudiante['programa'] == null ? '' : ' · ${estudiante['programa']}'}',
              ),
            ),
        ],
      ),
    );
    if (estudianteId == null) return;
    try {
      await ref.read(repositorioAdminProvider).crearInscripcion({
        'estudianteId': estudianteId,
        'grupoId': _grupoId,
      });
      await _cambiarGrupo(_grupoId);
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Map<String, dynamic>? get _grupoActual {
    for (final grupo in _grupos) {
      if ('${grupo['id']}' == _grupoId) return grupo;
    }
    return null;
  }

  List<String> get _programasDisponibles {
    final valores = <String, String>{};
    for (final grupo in _grupos) {
      final id = grupo['programaId'];
      if (id != null) valores['$id'] = '${grupo['programa'] ?? 'Sin programa'}';
    }
    return valores.keys.toList();
  }

  List<Map<String, dynamic>> get _gruposFiltrados {
    return _grupos.where((grupo) {
      if (_programaFiltro != null && '${grupo['programaId'] ?? ''}' != _programaFiltro) {
        return false;
      }
      if (_semestreFiltro != null && '${grupo['semestre'] ?? 1}' != '$_semestreFiltro') {
        return false;
      }
      return true;
    }).toList();
  }

  String _nombrePrograma(String? id) {
    for (final grupo in _grupos) {
      if ('${grupo['programaId']}' == id) return '${grupo['programa'] ?? 'Sin programa'}';
    }
    return 'Carrera';
  }

  List<int> get _semestresDisponibles {
    final valores = <int>{};
    for (final grupo in _grupos) {
      if (_programaFiltro != null && '${grupo['programaId'] ?? ''}' != _programaFiltro) continue;
      valores.add(int.tryParse('${grupo['semestre'] ?? 1}') ?? 1);
    }
    return valores.toList()..sort();
  }

  void _cambiarFiltros({String? programa, int? semestre}) {
    setState(() {
      if (programa != null) {
        _programaFiltro = programa;
        final disponibles = _semestresDisponibles;
        if (disponibles.isNotEmpty && !disponibles.contains(_semestreFiltro)) {
          _semestreFiltro = disponibles.first;
        }
      }
      if (semestre != null) _semestreFiltro = semestre;
    });
    final filtrados = _gruposFiltrados;
    final seleccionado = filtrados.isEmpty ? null : '${filtrados.first['id']}';
    if (seleccionado != null) {
      _cambiarGrupo(seleccionado);
    } else {
      setState(() {
        _grupoId = null;
        _inscripciones = const [];
      });
    }
  }

  List<Map<String, dynamic>> get _estudiantesFiltrados {
    final programaId = _grupoActual?['programaId'] as String?;
    if (programaId == null) return _estudiantes;
    return _estudiantes
        .where((estudiante) => '${estudiante['programaId'] ?? ''}' == programaId)
        .toList();
  }

  Future<void> _cambiarEstado(Map<String, dynamic> inscripcion) async {
    final estado = await showDialog<String>(
      context: context,
      builder: (contexto) => SimpleDialog(
        title: Text('${inscripcion['estudiante']}'),
        children: [
          for (final opcion in const ['ACTIVA', 'RETIRADA', 'APROBADA', 'REPROBADA'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(contexto).pop(opcion),
              child: Text(opcion),
            ),
        ],
      ),
    );
    if (estado == null) return;
    try {
      await ref.read(repositorioAdminProvider).actualizarInscripcion('${inscripcion['id']}', estado);
      await _cambiarGrupo(_grupoId);
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> inscripcion) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarInscripcion('${inscripcion['id']}');
      await _cambiarGrupo(_grupoId);
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _grupoId == null || _estudiantesFiltrados.isEmpty ? null : _crear,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Inscribir'),
      ),
      body: ListView(
        // Espacio inferior para que el botón flotante «crear» no tape el menú de acciones
        // (tres puntos) del último elemento de la lista.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _programaFiltro,
            decoration: const InputDecoration(labelText: 'Carrera / programa'),
            items: [
              for (final programa in _programasDisponibles)
                DropdownMenuItem(value: programa, child: Text(_nombrePrograma(programa))),
            ],
            onChanged: (valor) {
              if (valor != null) _cambiarFiltros(programa: valor);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _semestreFiltro,
            decoration: const InputDecoration(labelText: 'Semestre'),
            items: [
              for (final semestre in _semestresDisponibles)
                DropdownMenuItem(value: semestre, child: Text('Semestre $semestre')),
            ],
            onChanged: (valor) {
              if (valor != null) _cambiarFiltros(semestre: valor);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _grupoId,
            decoration: const InputDecoration(labelText: 'Materia / curso'),
            items: [
              for (final grupo in _gruposFiltrados)
                DropdownMenuItem(
                  value: '${grupo['id']}',
                  child: Text('${grupo['asignatura']} · Curso ${grupo['codigoCurso']}'),
                ),
            ],
            onChanged: _cambiarGrupo,
          ),
          if (_grupoActual?['programa'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Solo se muestran estudiantes de ${_grupoActual!['programa']}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          _ErrorTexto(_error),
          for (final inscripcion in _inscripciones)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('${inscripcion['estudiante']}'),
                subtitle: Text('${inscripcion['estado']}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (valor) {
                    if (valor == 'estado') _cambiarEstado(inscripcion);
                    if (valor == 'eliminar') _eliminar(inscripcion);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'estado', child: Text('Cambiar estado')),
                    PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
