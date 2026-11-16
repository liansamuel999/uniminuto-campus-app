import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../admin/data/repositorio_admin.dart';

/// Pestaña del administrador académico para horarios y salones.
///
/// El sistema asigna los salones solo (capacidad, laboratorio y choques de horario) y el
/// administrador puede volver a planificar todo o mover un horario a mano. La organización de
/// salones es interna: aquí solo se ve el resultado ya resuelto de cada grupo.
class PlanificacionTab extends ConsumerStatefulWidget {
  const PlanificacionTab({super.key});

  @override
  ConsumerState<PlanificacionTab> createState() => _PlanificacionTabState();
}

class _PlanificacionTabState extends ConsumerState<PlanificacionTab> {
  Map<String, dynamic> _resumen = const {};
  bool _cargando = true;
  bool _ejecutando = false;
  String? _error;

  RepositorioAdmin get _repo => ref.read(repositorioAdminProvider);

  static const List<String> _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

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
      final resumen = await _repo.planificacion();
      if (mounted) setState(() => _resumen = resumen);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _grupos => _mapas(_resumen['grupos']);
  List<Map<String, dynamic>> get _salones => _mapas(_resumen['salones']);

  static List<Map<String, dynamic>> _mapas(dynamic datos) =>
      (datos as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((fila) => Map<String, dynamic>.from(fila))
          .toList();

  Future<void> _planificar() async {
    setState(() => _ejecutando = true);
    try {
      final resultado = await _repo.planificarSalones();
      await _cargar();
      if (!mounted) return;
      final sinSalon = (resultado['sinSalon'] as List<dynamic>? ?? const []).whereType<Map>();
      await showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: const Text('Planificación terminada'),
          content: Text(
            'Horarios revisados: ${resultado['totalHorarios'] ?? 0}\n'
            'Con salón: ${resultado['asignados'] ?? 0}\n'
            'Movidos para resolver choques: ${resultado['movidos'] ?? 0}\n'
            'Sin salón: ${sinSalon.length}',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Entendido')),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _ejecutando = false);
    }
  }

  Future<void> _agregarClase(Map<String, dynamic> grupo) async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoNuevaClase(dias: _dias),
    );
    if (datos == null) return;
    try {
      final resultado = await _repo.crearHorarioAutomatico('${grupo['id']}', datos);
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clase asignada al salón ${resultado['salon'] ?? ''}')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  Future<void> _cambiarSalon(Map<String, dynamic> horario) async {
    final salonId = await showDialog<String>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Mover a otro salón'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final salon in _salones)
                ListTile(
                  dense: true,
                  leading: Icon(
                    salon['tipo'] == 'LABORATORIO' ? Icons.computer : Icons.meeting_room_outlined,
                  ),
                  title: Text('${salon['codigo']}'),
                  subtitle: Text('${salon['tipo']} · capacidad ${salon['capacidad']}'),
                  onTap: () => Navigator.of(contexto).pop('${salon['id']}'),
                ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Cancelar')),
        ],
      ),
    );
    if (salonId == null) return;
    try {
      await _repo.moverHorario('${horario['id']}', {'salonId': salonId});
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  Future<void> _quitarHorario(Map<String, dynamic> horario) async {
    try {
      await _repo.quitarHorario('${horario['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  Future<void> _quitarGrupo(Map<String, dynamic> grupo) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Quitar curso del periodo'),
        content: Text(
          'Se eliminarán el curso «${grupo['asignatura']}» (grupo ${grupo['grupo']}), '
          'sus horarios, su aula virtual y las inscripciones. El horario de los estudiantes '
          'se actualizará y dejará de mostrar esa materia.',
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(contexto).pop(true), child: const Text('Quitar curso')),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await _repo.quitarGrupo('${grupo['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
          Card(
            color: colores.primaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Salones y horarios', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  const Text(
                    'El sistema asigna los salones según capacidad, equipos y choques de horario. '
                    'Puedes volver a planificar todo o ajustar un horario a mano.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _ejecutando ? null : _planificar,
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(_ejecutando ? 'Planificando…' : 'Asignar salones automáticamente'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final grupo in _grupos) _tarjetaGrupo(context, grupo),
        ],
      ),
    );
  }

  Widget _tarjetaGrupo(BuildContext context, Map<String, dynamic> grupo) {
    final horarios = _mapas(grupo['horarios']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${grupo['codigoAsignatura']} · ${grupo['asignatura']} (Grupo ${grupo['grupo']})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (grupo['requiereLaboratorio'] == true)
                  const Chip(label: Text('Laboratorio'), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${grupo['periodo']} · ${grupo['estudiantes']} estudiante(s) · '
              'Docente: ${grupo['docente'] ?? 'Sin asignar'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (horarios.isEmpty)
              Row(
                children: [
                  const Expanded(child: Text('Sin horario asignado.')),
                  OutlinedButton.icon(
                    onPressed: () => _agregarClase(grupo),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar clase'),
                  ),
                ],
              )
            else
              for (final horario in horarios)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(
                    '${_dias[((horario['diaSemana'] as num?)?.toInt() ?? 1) - 1]} '
                    '${horario['horaInicio']}–${horario['horaFin']}',
                  ),
                  subtitle: Text('Salón ${horario['salon']}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (valor) {
                      if (valor == 'mover') _cambiarSalon(horario);
                      if (valor == 'quitar') _quitarHorario(horario);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'mover', child: Text('Mover de salón')),
                      PopupMenuItem(value: 'quitar', child: Text('Quitar horario')),
                    ],
                  ),
                ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _quitarGrupo(grupo),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Quitar curso'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogoNuevaClase extends StatefulWidget {
  const _DialogoNuevaClase({required this.dias});

  final List<String> dias;

  @override
  State<_DialogoNuevaClase> createState() => _DialogoNuevaClaseState();
}

class _DialogoNuevaClaseState extends State<_DialogoNuevaClase> {
  final _inicio = TextEditingController(text: '07:00');
  final _fin = TextEditingController(text: '09:00');
  int _dia = 1;
  String? _error;

  @override
  void dispose() {
    _inicio.dispose();
    _fin.dispose();
    super.dispose();
  }

  bool _horaValida(String valor) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(valor.trim());

  int _minutos(String valor) {
    final partes = valor.trim().split(':');
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }

  void _confirmar() {
    if (!_horaValida(_inicio.text) || !_horaValida(_fin.text)) {
      setState(() => _error = 'Usa el formato HH:MM (por ejemplo 07:00).');
      return;
    }
    if (_minutos(_fin.text) <= _minutos(_inicio.text)) {
      setState(() => _error = 'La hora de fin debe ser mayor que la de inicio.');
      return;
    }
    Navigator.of(context).pop({
      'diaSemana': _dia,
      'horaInicio': _inicio.text.trim(),
      'horaFin': _fin.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar clase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _dia,
            decoration: const InputDecoration(labelText: 'Día'),
            items: [
              for (final (indice, dia) in widget.dias.indexed)
                DropdownMenuItem(value: indice + 1, child: Text(dia)),
            ],
            onChanged: (valor) => setState(() => _dia = valor ?? 1),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inicio,
                  decoration: const InputDecoration(labelText: 'Inicio (HH:MM)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _fin,
                  decoration: const InputDecoration(labelText: 'Fin (HH:MM)'),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Text(
            'El salón se asigna automáticamente según capacidad y equipos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Agregar')),
      ],
    );
  }
}
