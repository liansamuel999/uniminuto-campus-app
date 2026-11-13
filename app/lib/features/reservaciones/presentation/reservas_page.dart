import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Reservas de cabinas y salas de autorecreación (6 individuales y 5 salas).
class ReservasPage extends ConsumerStatefulWidget {
  const ReservasPage({super.key});

  @override
  ConsumerState<ReservasPage> createState() => _ReservasPageState();
}

class _ReservasPageState extends ConsumerState<ReservasPage> {
  List<dynamic> _espacios = const [];
  List<dynamic> _mias = const [];
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
      final espacios = await api.getList('/reservaciones/espacios');
      final mias = await api.getList('/reservaciones/mias');
      if (!mounted) return;
      setState(() {
        _espacios = espacios;
        _mias = mias;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reservar(dynamic espacio) async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: ahora.add(const Duration(days: 1)),
      firstDate: DateTime(ahora.year, ahora.month, ahora.day),
      lastDate: ahora.add(const Duration(days: 30)),
      helpText: 'Día de la reserva',
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Hora de inicio (07:00 a 19:00)',
    );
    if (hora == null || !mounted) return;

    final inicio = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
    final fin = inicio.add(const Duration(hours: 1));

    try {
      await ref.read(apiClientProvider).postJson('/reservaciones', cuerpo: {
        'espacioId': '${espacio['id']}',
        'inicio': inicio.toUtc().toIso8601String(),
        'fin': fin.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reserva confirmada: ${espacio['nombre']}')),
      );
      await _cargar();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  Future<void> _cancelar(dynamic reserva) async {
    try {
      await ref.read(apiClientProvider).deleteJson('/reservaciones/${reserva['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final individuales = _espacios.where((e) => e['tipo'] == 'INDIVIDUAL').toList();
    final salas = _espacios.where((e) => e['tipo'] == 'GRUPO').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservas'),
        actions: [
          IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!),
              ),
            Text('Mis reservas', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_mias.isEmpty)
              const Text('Todavía no tienes reservas confirmadas.')
            else
              for (final reserva in _mias)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available),
                    title: Text('${reserva['espacioNombre']}'),
                    subtitle: Text(_rango(reserva['inicio'], reserva['fin'])),
                    trailing: IconButton(
                      tooltip: 'Cancelar',
                      onPressed: () => _cancelar(reserva),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
            const SizedBox(height: 20),
            if (individuales.isNotEmpty) ...[
              Text('Cabinas individuales', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...individuales.map(_tarjetaEspacio),
            ],
            if (salas.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Salas de grupo', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...salas.map(_tarjetaEspacio),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaEspacio(dynamic espacio) {
    final capacidad = (espacio['capacidad'] as num?)?.toInt() ?? 1;
    return Card(
      child: ListTile(
        leading: Icon(capacidad == 1 ? Icons.meeting_room_outlined : Icons.groups_outlined),
        title: Text('${espacio['nombre']}'),
        subtitle: Text(capacidad == 1 ? 'Individual · 30 a 120 min' : 'Hasta $capacidad personas · 30 a 120 min'),
        trailing: FilledButton(
          onPressed: () => _reservar(espacio),
          child: const Text('Reservar'),
        ),
      ),
    );
  }

  String _rango(dynamic inicio, dynamic fin) {
    final desde = DateTime.tryParse('$inicio')?.toLocal();
    final hasta = DateTime.tryParse('$fin')?.toLocal();
    if (desde == null || hasta == null) return '$inicio';
    String dos(int valor) => valor.toString().padLeft(2, '0');
    return '${dos(desde.day)}/${dos(desde.month)} ${dos(desde.hour)}:${dos(desde.minute)}'
        '–${dos(hasta.hour)}:${dos(hasta.minute)}';
  }
}
