import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';

/// Reservas de espacios de autorecreación: una semana, un día y franjas de 10 minutos
/// entre las 06:00 y las 20:00 (máximo 2 horas).
class ReservasPage extends ConsumerStatefulWidget {
  const ReservasPage({super.key});

  @override
  ConsumerState<ReservasPage> createState() => _ReservasPageState();
}

class _ReservasPageState extends ConsumerState<ReservasPage> {
  static const int apertura = 6 * 60;
  static const int cierre = 20 * 60;
  static const int paso = 10;
  static const int maximoMinutos = 120;

  final DateTime _hoy = DateTime.now();
  late DateTime _inicioSemana = _lunesDe(DateTime.now());
  late DateTime _diaSeleccionado = DateTime.now();

  List<Map<String, dynamic>> _espacios = const [];
  List<Map<String, dynamic>> _reservasSemana = const [];
  List<Map<String, dynamic>> _mias = const [];
  bool _cargando = true;
  String? _error;

  static DateTime _lunesDe(DateTime fecha) {
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    return dia.subtract(Duration(days: dia.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _diaSeleccionado = DateTime(_hoy.year, _hoy.month, _hoy.day);
    _cargar();
  }

  String _iso(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  static List<Map<String, dynamic>> _mapas(List<dynamic> datos) =>
      datos.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final api = ref.read(apiClientProvider);
      final semana = await api
          .getJson('/reservaciones/semana', parametros: {'desde': _iso(_inicioSemana)})
          .timeout(const Duration(seconds: 12));
      final mias = await api.getList('/reservaciones/mias').timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _espacios = _mapas(semana['espacios'] as List<dynamic>? ?? const []);
        _reservasSemana = _mapas(semana['reservas'] as List<dynamic>? ?? const []);
        _mias = _mapas(mias);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la disponibilidad. Revisa la conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<(int, int)> _ocupados(String espacioId) {
    final resultado = <(int, int)>[];
    for (final reserva in _reservasSemana) {
      if ('${reserva['espacioId']}' != espacioId) continue;
      final inicio = DateTime.tryParse('${reserva['inicio']}')?.toLocal();
      final fin = DateTime.tryParse('${reserva['fin']}')?.toLocal();
      if (inicio == null || fin == null) continue;
      final mismoDia = inicio.year == _diaSeleccionado.year &&
          inicio.month == _diaSeleccionado.month &&
          inicio.day == _diaSeleccionado.day;
      if (!mismoDia) continue;
      resultado.add((inicio.hour * 60 + inicio.minute, fin.hour * 60 + fin.minute));
    }
    return resultado;
  }

  String _hora(int minutos) =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';

  Future<void> _reservar(Map<String, dynamic> espacio) async {
    final seleccion = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaReserva(
        espacioNombre: '${espacio['nombre']}',
        ocupados: _ocupados('${espacio['id']}'),
        apertura: apertura,
        cierre: cierre,
        paso: paso,
        maximoMinutos: maximoMinutos,
        etiquetaHora: _hora,
      ),
    );
    if (seleccion == null || !mounted) return;

    final inicio = DateTime(
      _diaSeleccionado.year,
      _diaSeleccionado.month,
      _diaSeleccionado.day,
      seleccion.$1 ~/ 60,
      seleccion.$1 % 60,
    );
    final fin = inicio.add(Duration(minutes: seleccion.$2 - seleccion.$1));
    try {
      await ref.read(apiClientProvider).postJson('/reservaciones', cuerpo: {
        'espacioId': '${espacio['id']}',
        'inicio': inicio.toUtc().toIso8601String(),
        'fin': fin.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reservado: ${espacio['nombre']} · ${_hora(seleccion.$1)}–${_hora(seleccion.$2)}'),
        ),
      );
      await _cargar();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  Future<void> _cancelar(Map<String, dynamic> reserva) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: Text('¿Cancelar la reserva de ${reserva['espacioNombre']}?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.of(contexto).pop(true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await ref.read(apiClientProvider).deleteJson('/reservaciones/${reserva['id']}');
      await _cargar();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
    }
  }

  void _cambiarSemana(int delta) {
    setState(() {
      _inicioSemana = _inicioSemana.add(Duration(days: 7 * delta));
      _diaSeleccionado = _inicioSemana;
    });
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final dias = List<DateTime>.generate(7, (indice) => _inicioSemana.add(Duration(days: indice)));
    final puedeRetroceder = _inicioSemana.isAfter(_lunesDe(_hoy));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservas'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Semana anterior',
                  onPressed: puedeRetroceder ? () => _cambiarSemana(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_fechaCorta(dias.first)} – ${_fechaCorta(dias.last)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Semana siguiente',
                  onPressed: () => _cambiarSemana(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final dia in dias)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _BotonDia(
                        dia: dia,
                        seleccionado: dia.year == _diaSeleccionado.year &&
                            dia.month == _diaSeleccionado.month &&
                            dia.day == _diaSeleccionado.day,
                        esHoy: dia.year == _hoy.year && dia.month == _hoy.month && dia.day == _hoy.day,
                        etiqueta: _diaSemana(dia),
                        onTap: () => setState(() => _diaSeleccionado = dia),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colores.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!),
              ),
            if (_mias.isNotEmpty) ...[
              Text('Mis reservas', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final reserva in _mias.take(5))
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
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
              const SizedBox(height: 12),
            ],
            Text(
              'Disponibilidad del ${_fechaCorta(_diaSeleccionado)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (!_cargando && _error == null && _espacios.isEmpty)
              const Text('No hay espacios configurados para reservar.'),
            for (final espacio in _espacios) _tarjetaEspacio(context, espacio),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaEspacio(BuildContext context, Map<String, dynamic> espacio) {
    final ocupados = _ocupados('${espacio['id']}');
    final capacidad = (espacio['capacidad'] as num?)?.toInt() ?? 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(capacidad == 1 ? Icons.meeting_room_outlined : Icons.groups_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${espacio['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                FilledButton.tonal(onPressed: () => _reservar(espacio), child: const Text('Reservar')),
              ],
            ),
            const SizedBox(height: 6),
            if (ocupados.isEmpty)
              Text('Libre todo el día (06:00–20:00)',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final rango in ocupados)
                    Chip(
                      label: Text('Ocupado ${_hora(rango.$1)}–${_hora(rango.$2)}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _rango(dynamic inicio, dynamic fin) {
    final desde = DateTime.tryParse('$inicio')?.toLocal();
    final hasta = DateTime.tryParse('$fin')?.toLocal();
    if (desde == null || hasta == null) return 'Reserva';
    return '${fechaCorta(desde)} ${_hora(desde.hour * 60 + desde.minute)}–${_hora(hasta.hour * 60 + hasta.minute)}';
  }

  String _fechaCorta(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}';

  String _diaSemana(DateTime fecha) {
    const nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return nombres[fecha.weekday - 1];
  }
}

class _BotonDia extends StatelessWidget {
  const _BotonDia({
    required this.dia,
    required this.seleccionado,
    required this.esHoy,
    required this.etiqueta,
    required this.onTap,
  });

  final DateTime dia;
  final bool seleccionado;
  final bool esHoy;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Material(
      color: seleccionado ? colores.primary : colores.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: esHoy ? colores.primary : colores.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 10,
                  color: seleccionado ? colores.onPrimary : colores.onSurfaceVariant,
                ),
              ),
              Text(
                '${dia.day}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: seleccionado ? colores.onPrimary : colores.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja inferior con selección de hora de inicio y fin en una sola pantalla.
class _HojaReserva extends StatefulWidget {
  const _HojaReserva({
    required this.espacioNombre,
    required this.ocupados,
    required this.apertura,
    required this.cierre,
    required this.paso,
    required this.maximoMinutos,
    required this.etiquetaHora,
  });

  final String espacioNombre;
  final List<(int, int)> ocupados;
  final int apertura;
  final int cierre;
  final int paso;
  final int maximoMinutos;
  final String Function(int) etiquetaHora;

  @override
  State<_HojaReserva> createState() => _HojaReservaState();
}

class _HojaReservaState extends State<_HojaReserva> {
  int? _inicio;

  bool _choca(int desde, int hasta) =>
      widget.ocupados.any((rango) => desde < rango.$2 && hasta > rango.$1);

  List<int> get _inicios => [
        for (var minuto = widget.apertura; minuto + widget.paso <= widget.cierre; minuto += widget.paso)
          if (!_choca(minuto, minuto + widget.paso)) minuto,
      ];

  List<int> get _fines {
    final inicio = _inicio;
    if (inicio == null) return const [];
    return [
      for (var fin = inicio + widget.paso;
          fin <= inicio + widget.maximoMinutos && fin <= widget.cierre;
          fin += widget.paso)
        if (!_choca(inicio, fin)) fin,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final inicios = _inicios;
    final fines = _fines;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reservar ${widget.espacioNombre}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (inicios.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No hay horas libres este día.'),
              )
            else ...[
              DropdownButtonFormField<int>(
                initialValue: _inicio,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Hora de inicio'),
                items: [
                  for (final minuto in inicios)
                    DropdownMenuItem(value: minuto, child: Text(widget.etiquetaHora(minuto))),
                ],
                onChanged: (valor) => setState(() => _inicio = valor),
              ),
              const SizedBox(height: 10),
              if (_inicio != null)
                DropdownButtonFormField<int>(
                  key: ValueKey(_inicio),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Hora de fin (máx. 2 h)'),
                  items: [
                    for (final minuto in fines)
                      DropdownMenuItem(
                        value: minuto,
                        child: Text(
                          '${widget.etiquetaHora(minuto)} (${minuto - _inicio!} min)',
                        ),
                      ),
                  ],
                  onChanged: (valor) {
                    if (valor != null) Navigator.of(context).pop((_inicio!, valor));
                  },
                ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
            ),
          ],
        ),
      ),
    );
  }
}
