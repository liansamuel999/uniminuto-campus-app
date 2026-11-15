import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Visor de auditoría de solo lectura para el rol Auditor (§8.1, Fase 5).
class AuditoriaPage extends ConsumerStatefulWidget {
  const AuditoriaPage({super.key});

  @override
  ConsumerState<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends ConsumerState<AuditoriaPage> {
  List<Map<String, dynamic>> _eventos = const [];
  List<String> _acciones = const [];
  bool _cargando = true;
  String? _error;
  String? _accion;
  DateTime? _desde;
  DateTime? _hasta;

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
      final acciones = await repo.accionesAuditoria();
      final eventos = await repo.auditoria(
        accion: _accion,
        desde: _desde?.toUtc().toIso8601String(),
        hasta: _hasta?.toUtc().toIso8601String(),
        limite: 100,
      );
      if (!mounted) return;
      setState(() {
        _acciones = acciones.map((accion) => '$accion').toList();
        _eventos = eventos
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

  Future<void> _elegirFecha({required bool esDesde}) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2027, 12, 31),
    );
    if (fecha == null) return;
    setState(() {
      if (esDesde) {
        _desde = DateTime(fecha.year, fecha.month, fecha.day);
      } else {
        _hasta = DateTime(fecha.year, fecha.month, fecha.day, 23, 59, 59);
      }
    });
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _accion,
              decoration: const InputDecoration(labelText: 'Acción'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas las acciones')),
                for (final accion in _acciones)
                  DropdownMenuItem<String?>(value: accion, child: Text(accion)),
              ],
              onChanged: (valor) {
                setState(() => _accion = valor);
                _cargar();
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _elegirFecha(esDesde: true),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(_desde == null ? 'Desde' : _fecha(_desde!)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _elegirFecha(esDesde: false),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: Text(_hasta == null ? 'Hasta' : _fecha(_hasta!)),
                ),
                if (_desde != null || _hasta != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _desde = null;
                        _hasta = null;
                      });
                      _cargar();
                    },
                    child: const Text('Limpiar fechas'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
            if (!_cargando && _error == null && _eventos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No hay eventos de auditoría con esos filtros.'),
              ),
            for (final evento in _eventos)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    switch ('${evento['accion']}') {
                      'VALIDAR_ACCESO' => Icons.qr_code_scanner,
                      'CAMBIO_NOTA' => Icons.grading_outlined,
                      'ASIGNAR_DOCENTE' => Icons.person_add_alt,
                      _ => Icons.shield_outlined,
                    },
                  ),
                  title: Text('${evento['accion']} · ${evento['resultado']}'),
                  subtitle: Text(
                    '${_fechaHora(evento['timestamp'])}\n'
                    '${evento['recurso']}\n'
                    '${evento['actor'] is Map ? (evento['actor'] as Map)['nombre'] : 'Sistema'}',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fecha(DateTime valor) =>
      '${valor.day.toString().padLeft(2, '0')}/${valor.month.toString().padLeft(2, '0')}/${valor.year}';

  String _fechaHora(dynamic iso) {
    final fecha = DateTime.tryParse('$iso')?.toLocal();
    if (fecha == null) return '$iso';
    return '${_fecha(fecha)} ${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
  }
}
