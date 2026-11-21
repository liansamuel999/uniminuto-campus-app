import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Capa curada del data lake: ETL bajo demanda y lectura de los agregados de analítica.
class AnaliticaTab extends ConsumerStatefulWidget {
  const AnaliticaTab({super.key});

  @override
  ConsumerState<AnaliticaTab> createState() => _AnaliticaTabState();
}

class _AnaliticaTabState extends ConsumerState<AnaliticaTab> {
  Map<String, dynamic>? _resumen;
  bool _cargando = true;
  bool _ejecutando = false;
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
      final datos = await ref.read(repositorioAdminProvider).analitica();
      if (mounted) setState(() => _resumen = datos);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la analítica.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _ejecutar() async {
    setState(() {
      _ejecutando = true;
      _error = null;
    });
    try {
      final datos = await ref.read(repositorioAdminProvider).ejecutarEtl();
      if (mounted) {
        setState(() => _resumen = datos);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ETL ejecutado: datos procesados y agregados actualizados.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _ejecutando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final ejecucion = _resumen?['ejecucion'] as Map<String, dynamic>?;
    final metricas = ((_resumen?['metricas'] as List<dynamic>?) ?? const [])
        .whereType<Map>()
        .map((fila) => Map<String, dynamic>.from(fila))
        .toList();
    final porCategoria = <String, List<Map<String, dynamic>>>{};
    for (final metrica in metricas) {
      porCategoria.putIfAbsent('${metrica['categoria']}', () => []).add(metrica);
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ejecutando ? null : _ejecutar,
        icon: _ejecutando
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow),
        label: const Text('Ejecutar ETL'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Text(
              'Data lake y analítica académica',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'El ETL extrae datos operativos, escribe un archivo JSONL en el bucket y publica '
              'agregados para el panel. Es la capa curada del data lake.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colores.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!),
              ),
            if (ejecucion != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text('Última ejecución: ${_fecha('${ejecucion['generadoEn']}')}'),
                  subtitle: Text(
                    '${ejecucion['filas']} filas procesadas'
                    '${ejecucion['objetoKey'] == null ? ' · sin objeto en S3' : ' · ${ejecucion['objetoKey']}'}',
                  ),
                ),
              ),
            if (!_cargando && metricas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Todavía no hay agregados. Pulsa «Ejecutar ETL» para procesar los datos de la muestra.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final entrada in porCategoria.entries) ...[
              const SizedBox(height: 12),
              Text(
                _tituloCategoria(entrada.key),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Card(
                child: Column(
                  children: [
                    for (final metrica in entrada.value)
                      ListTile(
                        dense: true,
                        title: Text('${metrica['etiqueta']}'),
                        trailing: Text(
                          _valor(entrada.key, metrica),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: _detalle(metrica),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _tituloCategoria(String categoria) => switch (categoria) {
        'programa' => 'Estudiantes por programa',
        'curso' => 'Cursos: promedio y aprobación',
        'entrega' => 'Entregas por estado',
        'actividad' => 'Actividades por tipo',
        'incidencia' => 'Incidencias por estado',
        'reserva' => 'Reservas activas por espacio',
        'acceso' => 'Accesos',
        _ => categoria,
      };

  String _valor(String categoria, Map<String, dynamic> metrica) {
    final valor = (metrica['valor'] as num?)?.toDouble() ?? 0;
    if (categoria == 'curso') return valor.toStringAsFixed(2);
    return valor.toStringAsFixed(valor.truncateToDouble() == valor ? 0 : 2);
  }

  Widget? _detalle(Map<String, dynamic> metrica) {
    final detalle = metrica['detalle'];
    if (detalle is! Map) return null;
    if (detalle['estudiantes'] != null) {
      return Text(
        '${detalle['estudiantes']} estudiantes · ${detalle['aprobados'] ?? 0} aprobados'
        '${detalle['programa'] == null ? '' : ' · ${detalle['programa']}'}',
      );
    }
    if (detalle['cursos'] != null) return Text('${detalle['cursos']} cursos');
    return null;
  }
}

String _fecha(String iso) {
  final fecha = DateTime.tryParse(iso)?.toLocal();
  if (fecha == null) return iso;
  return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
      '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
}
