import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Panel del Admin de Espacios: catálogo Edificio → Piso → Salón y asignación de salones (§5).
class AdminEspaciosPage extends ConsumerWidget {
  const AdminEspaciosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Espacios y horarios'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Edificios'),
              Tab(text: 'Pisos'),
              Tab(text: 'Salones'),
              Tab(text: 'Horarios'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_EdificiosTab(), _PisosTab(), _SalonesTab(), _HorariosTab()],
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

const _dias = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

// ───────────────────────────────── Edificios ────────────────────────────────
class _EdificiosTab extends ConsumerStatefulWidget {
  const _EdificiosTab();

  @override
  ConsumerState<_EdificiosTab> createState() => _EdificiosTabState();
}

class _EdificiosTabState extends ConsumerState<_EdificiosTab> {
  List<Map<String, dynamic>> _edificios = const [];
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
      final datos = await ref.read(repositorioAdminProvider).edificios();
      if (mounted) setState(() => _edificios = _aMapas(datos));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editar([Map<String, dynamic>? actual]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _DialogoEdificio(actual: actual),
    );
    if (datos == null) return;
    try {
      final repo = ref.read(repositorioAdminProvider);
      if (actual == null) {
        await repo.crearEdificio(datos);
      } else {
        await repo.actualizarEdificio('${actual['id']}', datos);
      }
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> edificio) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarEdificio('${edificio['id']}');
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
        label: const Text('Edificio'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final edificio in _edificios)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: Text('${edificio['codigo']} · ${edificio['nombre']}'),
                subtitle: Text('Sede ${edificio['sede']} · ${edificio['pisos']} piso(s)'),
                trailing: PopupMenuButton<String>(
                  onSelected: (valor) {
                    if (valor == 'editar') _editar(edificio);
                    if (valor == 'eliminar') _eliminar(edificio);
                  },
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

class _DialogoEdificio extends StatefulWidget {
  const _DialogoEdificio({this.actual});

  final Map<String, dynamic>? actual;

  @override
  State<_DialogoEdificio> createState() => _DialogoEdificioState();
}

class _DialogoEdificioState extends State<_DialogoEdificio> {
  late final TextEditingController _codigo = TextEditingController(text: '${widget.actual?['codigo'] ?? ''}');
  late final TextEditingController _nombre = TextEditingController(text: '${widget.actual?['nombre'] ?? ''}');

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.actual == null ? 'Nuevo edificio' : 'Editar edificio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _codigo, decoration: const InputDecoration(labelText: 'Código')),
          TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'codigo': _codigo.text.trim(),
            'nombre': _nombre.text.trim(),
            'sede': 'CALLE_80',
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────── Pisos ──────────────────────────────────
class _PisosTab extends ConsumerStatefulWidget {
  const _PisosTab();

  @override
  ConsumerState<_PisosTab> createState() => _PisosTabState();
}

class _PisosTabState extends ConsumerState<_PisosTab> {
  List<Map<String, dynamic>> _edificios = const [];
  List<Map<String, dynamic>> _pisos = const [];
  String? _edificioId;
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
      final edificios = await repo.edificios();
      final seleccionado = _edificioId ?? (edificios.isEmpty ? null : '${(edificios.first as Map)['id']}');
      final pisos = seleccionado == null ? <dynamic>[] : await repo.pisos(seleccionado);
      if (!mounted) return;
      setState(() {
        _edificios = _aMapas(edificios);
        _edificioId = seleccionado;
        _pisos = _aMapas(pisos);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarEdificio(String? id) async {
    if (id == null) return;
    setState(() {
      _edificioId = id;
      _cargando = true;
    });
    try {
      final datos = await ref.read(repositorioAdminProvider).pisos(id);
      if (!mounted) return;
      setState(() => _pisos = _aMapas(datos));
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _crearPiso() async {
    if (_edificioId == null) return;
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _DialogoPiso(),
    );
    if (datos == null) return;
    try {
      await ref.read(repositorioAdminProvider).crearPiso({...datos, 'edificioId': _edificioId});
      await _cambiarEdificio(_edificioId);
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _crearSalon(Map<String, dynamic> piso) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _DialogoSalon(),
    );
    if (datos == null) return;
    try {
      await ref.read(repositorioAdminProvider).crearSalon({...datos, 'pisoId': '${piso['id']}'});
      await _cambiarEdificio(_edificioId);
      if (mounted) _aviso(context, 'Salón creado en el piso ${piso['numero']}.');
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminarPiso(Map<String, dynamic> piso) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarPiso('${piso['id']}');
      await _cambiarEdificio(_edificioId);
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edificioId == null ? null : _crearPiso,
        icon: const Icon(Icons.add),
        label: const Text('Piso'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _edificioId,
            decoration: const InputDecoration(labelText: 'Edificio'),
            items: [
              for (final edificio in _edificios)
                DropdownMenuItem(value: '${edificio['id']}', child: Text('${edificio['codigo']} · ${edificio['nombre']}')),
            ],
            onChanged: _cambiarEdificio,
          ),
          const SizedBox(height: 8),
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final piso in _pisos)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text('${piso['numero']}')),
                title: Text('Piso ${piso['numero']} · ${piso['tipo']}'),
                subtitle: Text('${piso['salones']} salón(es)'),
                trailing: PopupMenuButton<String>(
                  onSelected: (valor) {
                    if (valor == 'salon') _crearSalon(piso);
                    if (valor == 'eliminar') _eliminarPiso(piso);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'salon', child: Text('Añadir salón')),
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

class _DialogoPiso extends StatefulWidget {
  const _DialogoPiso();

  @override
  State<_DialogoPiso> createState() => _DialogoPisoState();
}

class _DialogoPisoState extends State<_DialogoPiso> {
  final _numero = TextEditingController();
  String _tipo = 'ESTUDIANTIL';

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo piso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _numero,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Número'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(value: 'ESTUDIANTIL', child: Text('Estudiantil')),
              DropdownMenuItem(value: 'ADMINISTRATIVO', child: Text('Administrativo')),
            ],
            onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'numero': int.tryParse(_numero.text.trim()) ?? 0,
            'tipo': _tipo,
          }),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _DialogoSalon extends StatefulWidget {
  const _DialogoSalon();

  @override
  State<_DialogoSalon> createState() => _DialogoSalonState();
}

class _DialogoSalonState extends State<_DialogoSalon> {
  final _codigo = TextEditingController();
  final _capacidad = TextEditingController(text: '30');
  String _tipo = 'AULA';

  @override
  void dispose() {
    _codigo.dispose();
    _capacidad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo salón'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _codigo, decoration: const InputDecoration(labelText: 'Código')),
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(value: 'AULA', child: Text('Aula')),
              DropdownMenuItem(value: 'LABORATORIO', child: Text('Laboratorio')),
              DropdownMenuItem(value: 'OFICINA', child: Text('Oficina')),
            ],
            onChanged: (valor) => setState(() => _tipo = valor ?? _tipo),
          ),
          TextField(
            controller: _capacidad,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Capacidad'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'codigo': _codigo.text.trim(),
            'tipo': _tipo,
            'capacidad': int.tryParse(_capacidad.text.trim()) ?? 0,
          }),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────── Salones ────────────────────────────────
class _SalonesTab extends ConsumerStatefulWidget {
  const _SalonesTab();

  @override
  ConsumerState<_SalonesTab> createState() => _SalonesTabState();
}

class _SalonesTabState extends ConsumerState<_SalonesTab> {
  List<Map<String, dynamic>> _salones = const [];
  String? _filtroEdificio;
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
      final datos = await ref.read(repositorioAdminProvider).salonesTodos();
      if (mounted) setState(() => _salones = _aMapas(datos));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> salon) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarSalon('${salon['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final edificios = _salones.map((salon) => '${salon['edificioCodigo']}').toSet().toList()..sort();
    final visibles = _filtroEdificio == null
        ? _salones
        : _salones.where((salon) => '${salon['edificioCodigo']}' == _filtroEdificio).toList();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _filtroEdificio,
            decoration: const InputDecoration(labelText: 'Filtrar por edificio'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              for (final edificio in edificios)
                DropdownMenuItem<String?>(value: edificio, child: Text('Edificio $edificio')),
            ],
            onChanged: (valor) => setState(() => _filtroEdificio = valor),
          ),
          const SizedBox(height: 8),
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final salon in visibles)
            Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.meeting_room_outlined),
                title: Text('${salon['codigo']}'),
                subtitle: Text(
                  '${salon['tipo']} · capacidad ${salon['capacidad']} · '
                  '${salon['edificioCodigo']} piso ${salon['piso']}',
                ),
                trailing: IconButton(
                  tooltip: 'Eliminar salón',
                  onPressed: () => _eliminar(salon),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────── Horarios ───────────────────────────────
class _HorariosTab extends ConsumerStatefulWidget {
  const _HorariosTab();

  @override
  ConsumerState<_HorariosTab> createState() => _HorariosTabState();
}

class _HorariosTabState extends ConsumerState<_HorariosTab> {
  List<Map<String, dynamic>> _horarios = const [];
  List<Map<String, dynamic>> _grupos = const [];
  List<Map<String, dynamic>> _salones = const [];
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
      final resultados = await Future.wait([repo.horarios(), repo.grupos(), repo.salonesTodos()]);
      if (!mounted) return;
      setState(() {
        _horarios = _aMapas(resultados[0]);
        _grupos = _aMapas(resultados[1]);
        _salones = _aMapas(resultados[2]);
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
      builder: (_) => _DialogoHorario(grupos: _grupos, salones: _salones),
    );
    if (datos == null) return;
    try {
      await ref.read(repositorioAdminProvider).crearHorario(datos);
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> horario) async {
    try {
      await ref.read(repositorioAdminProvider).eliminarHorario('${horario['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) _aviso(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _grupos.isEmpty || _salones.isEmpty ? null : _crear,
        icon: const Icon(Icons.add),
        label: const Text('Horario'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final horario in _horarios)
            Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                dense: true,
                leading: Text(_dias[(horario['diaSemana'] as num?)?.toInt() ?? 1]),
                title: Text('${horario['asignatura']} · Grupo ${horario['grupo']}'),
                subtitle: Text(
                  '${horario['horaInicio']}–${horario['horaFin']} · Salón ${horario['salon']}',
                ),
                trailing: IconButton(
                  tooltip: 'Eliminar horario',
                  onPressed: () => _eliminar(horario),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogoHorario extends StatefulWidget {
  const _DialogoHorario({required this.grupos, required this.salones});

  final List<Map<String, dynamic>> grupos;
  final List<Map<String, dynamic>> salones;

  @override
  State<_DialogoHorario> createState() => _DialogoHorarioState();
}

class _DialogoHorarioState extends State<_DialogoHorario> {
  String? _grupoId;
  String? _salonId;
  int _dia = 1;
  final _inicio = TextEditingController(text: '07:00');
  final _fin = TextEditingController(text: '09:00');

  @override
  void initState() {
    super.initState();
    _grupoId = widget.grupos.isEmpty ? null : '${widget.grupos.first['id']}';
    _salonId = widget.salones.isEmpty ? null : '${widget.salones.first['id']}';
  }

  @override
  void dispose() {
    _inicio.dispose();
    _fin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Asignar salón a horario'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _grupoId,
              decoration: const InputDecoration(labelText: 'Grupo'),
              items: [
                for (final grupo in widget.grupos)
                  DropdownMenuItem(
                    value: '${grupo['id']}',
                    child: Text('${grupo['asignatura']} · ${grupo['periodo']}'),
                  ),
              ],
              onChanged: (valor) => setState(() => _grupoId = valor),
            ),
            DropdownButtonFormField<String>(
              initialValue: _salonId,
              decoration: const InputDecoration(labelText: 'Salón'),
              items: [
                for (final salon in widget.salones)
                  DropdownMenuItem(
                    value: '${salon['id']}',
                    child: Text('${salon['codigo']} · ${salon['edificioCodigo']} piso ${salon['piso']}'),
                  ),
              ],
              onChanged: (valor) => setState(() => _salonId = valor),
            ),
            DropdownButtonFormField<int>(
              initialValue: _dia,
              decoration: const InputDecoration(labelText: 'Día'),
              items: [
                for (var dia = 1; dia <= 7; dia += 1)
                  DropdownMenuItem(value: dia, child: Text(_dias[dia])),
              ],
              onChanged: (valor) => setState(() => _dia = valor ?? _dia),
            ),
            TextField(controller: _inicio, decoration: const InputDecoration(labelText: 'Inicio (HH:MM)')),
            TextField(controller: _fin, decoration: const InputDecoration(labelText: 'Fin (HH:MM)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'grupoId': _grupoId,
            'salonId': _salonId,
            'diaSemana': _dia,
            'horaInicio': _inicio.text.trim(),
            'horaFin': _fin.text.trim(),
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
