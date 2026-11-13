import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Notas del estudiante por asignatura, corte y actividad (§6.4).
class NotasPage extends ConsumerStatefulWidget {
  const NotasPage({super.key});

  @override
  ConsumerState<NotasPage> createState() => _NotasPageState();
}

class _NotasPageState extends ConsumerState<NotasPage> {
  List<dynamic> _notas = const [];
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
      final notas = await ref.read(apiClientProvider).getList('/mis-notas');
      if (mounted) setState(() => _notas = notas);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis notas'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_cargando && _notas.isEmpty) const Text('Todavía no hay notas para el periodo activo.'),
            for (final asignatura in _notas) _TarjetaAsignatura(asignatura: asignatura),
          ],
        ),
      ),
    );
  }
}

class _TarjetaAsignatura extends StatelessWidget {
  const _TarjetaAsignatura({required this.asignatura});

  final dynamic asignatura;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final definitiva = (asignatura['definitiva'] as num?)?.toDouble() ?? 0;
    final cortes = asignatura['cortes'] as List<dynamic>? ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${asignatura['asignatura']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${asignatura['codigo']}',
                          style: TextStyle(color: colores.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                Chip(
                  label: Text('Definitiva ${definitiva.toStringAsFixed(2)}'),
                  backgroundColor: definitiva >= 3
                      ? const Color(0xFFE3F5E8)
                      : colores.errorContainer,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final corte in cortes) ...[
              Row(
                children: [
                  Text('Corte ${corte['numero']}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Text('(${corte['peso']}%)',
                      style: TextStyle(color: colores.onSurfaceVariant, fontSize: 12)),
                  const Spacer(),
                  Text(
                    corte['nota'] == null ? 'Sin nota' : (corte['nota'] as num).toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              for (final actividad in (corte['actividades'] as List<dynamic>? ?? const []))
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${actividad['titulo']} · ${actividad['peso']}%',
                          style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        actividad['nota'] == null
                            ? '—'
                            : (actividad['nota'] as num).toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: actividad['nota'] == null ? colores.outline : colores.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              if (corte != cortes.last) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}
