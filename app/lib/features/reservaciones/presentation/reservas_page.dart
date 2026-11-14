import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Reservas por semana: calendario de 7 días, horas libres por sala y bloques de 10 minutos
/// entre las 06:00 y las 20:00, con un máximo de 2 horas.
///
/// Nota de layout: la tira de días usa un `Row` con hijos `Expanded` (no un `ListView`
/// horizontal anidado) para evitar problemas de restricciones dentro del scroll principal.
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
  late DateTime _inicioSemana = _lunesDe(_hoy);
  late DateTime _diaSeleccionado = DateTime(_hoy.year, _hoy.month, _hoy.day);

  List<dynamic> _espacios = const [];
  List<dynamic> _reservasSemana = const [];
  List<dynamic> _mias = const [];
  bool _cargando = true;
  String? _error;

  static DateTime _lunesDe(DateTime fecha) {
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    return dia.subtract(Duration(days: dia.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _iso(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  Future<void> _cargar() async {
    if (_cargando && _espacios.isNotEmpty) return;
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    final api = ref.read(apiClientProvider);
    try {
      // Query como parámetro (no incrustada en la ruta) y con tiempo límite para no dejar
      // la pantalla en carga indefinida si la red se queda colgada.
      final semana = await api
          .getJson('/reservaciones/semana', parametros: {'desde': _iso(_inicioSemana)})
          .timeout(const Duration(seconds: 12));
      final mias = await api
          .getList('/reservaciones/mias')
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _espacios = semana['espacios'] as List<dynamic>? ?? const [];
        _reservasSemana = semana['reservas'] as List<dynamic>? ?? const [];
        _mias = mias;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la disponibilidad. Revisa la conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<dynamic> _reservasDelDia(String espacioId) {
    return _reservasSemana.where((reserva) {
      final inicio = DateTime.tryParse('${reserva['inicio']}')?.toLocal();
      if (inicio == null) return false;
      final mismoDia = inicio.year == _diaSeleccionado.year &&
          inicio.month == _diaSeleccionado.month &&
          inicio.day == _diaSeleccionado.day;
      return mismoDia && '${reserva['espacioId']}' == espacioId;
    }).toList();
  }

  List<(int, int)> _ocupados(String espacioId) {
    return _reservasDelDia(espacioId).map((reserva) {
      final inicio = DateTime.parse('${reserva['inicio']}').toLocal();
      final fin = DateTime.parse('${reserva['fin']}').toLocal();
      return (inicio.hour * 60 + inicio.minute, fin.hour * 60 + fin.minute);
    }).toList();
  }

  String _hora(int minutos) =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';

  Future<void> _reservar(dynamic espacio) async {
    final ocupados = _ocupados('${espacio['id']}');
    final inicioElegido = await showDialog<int>(
      context: context,
      builder: (_) => _DialogoSeleccion(
        titulo: 'Hora de inicio',
        opciones: [
          for (var minuto = apertura; minuto + paso <= cierre; minuto += paso)
            if (!ocupados.any((rango) => minuto < rango.$2 && minuto + paso > rango.$1)) minuto,
        ],
        etiqueta: _hora,
        vacio: 'No hay horas libres este día.',
      ),
    );
    if (inicioElegido == null || !mounted) return;

    final finElegido = await showDialog<int>(
      context: context,
      builder: (_) => _DialogoSeleccion(
        titulo: 'Hora de fin (máx. 2 h)',
        opciones: [
          for (var fin = inicioElegido + paso;
              fin <= inicioElegido + maximoMinutos && fin <= cierre;
              fin += paso)
            if (!ocupados.any((rango) => inicioElegido < rango.$2 && fin > rango.$1)) fin,
        ],
        etiqueta: (minuto) => '${_hora(minuto)} (${minuto - inicioElegido} min)',
        vacio: 'No hay franjas disponibles desde esa hora.',
      ),
    );
    if (finElegido == null || !mounted) return;

    final inicio = DateTime(
      _diaSeleccionado.year,
      _diaSeleccionado.month,
      _diaSeleccionado.day,
      inicioElegido ~/ 60,
      inicioElegido % 60,
    );
    final fin = inicio.add(Duration(minutes: finElegido - inicioElegido));

    try {
      await ref.read(apiClientProvider).postJson('/reservaciones', cuerpo: {
        'espacioId': '${espacio['id']}',
        'inicio': inicio.toUtc().toIso8601String(),
        'fin': fin.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reservado: ${espacio['nombre']} · ${_hora(inicioElegido)}–${_hora(finElegido)}')),
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
    final colores = Theme.of(context).colorScheme;
    final dias = List<DateTime>.generate(7, (indice) => _inicioSemana.add(Duration(days: indice)));

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
                  onPressed: _inicioSemana.isAfter(_lunesDe(_hoy))
                      ? () {
                          setState(() {
                            _inicioSemana = _inicioSemana.subtract(const Duration(days: 7));
                            _diaSeleccionado = _inicioSemana;
                          });
                          _cargar();
                        }
                      : null,
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
                  onPressed: () {
                    setState(() {
                      _inicioSemana = _inicioSemana.add(const Duration(days: 7));
                      _diaSeleccionado = _inicioSemana;
                    });
                    _cargar();
                  },
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
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colores.errorContainer, borderRadius: BorderRadius.circular(12)),
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
            for (final espacio in _espacios) _tarjetaEspacio(espacio),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaEspacio(dynamic espacio) {
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
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _reservar(espacio),
                  child: const Text('Reservar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (ocupados.isEmpty)
              Text('Libre todo el día (06:00–20:00)', style: TextStyle(color: Theme.of(context).colorScheme.primary))
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
    if (desde == null || hasta == null) return '$inicio';
    return '${_fechaCorta(desde)} ${_hora(desde.hour * 60 + desde.minute)}–${_hora(hasta.hour * 60 + hasta.minute)}';
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
          height: 62,
          padding: const EdgeInsets.symmetric(vertical: 6),
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
                  fontSize: 18,
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

/// Diálogo de selección de un minuto concreto (lista acotada, sin scrollables anidados).
class _DialogoSeleccion extends StatelessWidget {
  const _DialogoSeleccion({
    required this.titulo,
    required this.opciones,
    required this.etiqueta,
    required this.vacio,
  });

  final String titulo;
  final List<int> opciones;
  final String Function(int) etiqueta;
  final String vacio;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Flexible(
                child: opciones.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(vacio),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: opciones.length,
                        itemBuilder: (contexto, indice) {
                          final minuto = opciones[indice];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(etiqueta(minuto)),
                            onTap: () => Navigator.of(contexto).pop(minuto),
                          );
                        },
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
