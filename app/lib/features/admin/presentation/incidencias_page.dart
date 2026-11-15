import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';

/// Incidencias: cualquier rol reporta y ve las propias; Soporte las gestiona (§5, D-50).
class IncidenciasPage extends ConsumerStatefulWidget {
  const IncidenciasPage({super.key});

  @override
  ConsumerState<IncidenciasPage> createState() => _IncidenciasPageState();
}

class _IncidenciasPageState extends ConsumerState<IncidenciasPage> {
  List<Map<String, dynamic>> _incidencias = const [];
  bool _cargando = true;
  String? _error;
  String? _filtroEstado;

  bool get _esSoporte {
    final sesion = ref.read(sesionProvider).valueOrNull;
    return sesion?.roles.contains('SOPORTE') ?? false;
  }

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
      final datos = _esSoporte
          ? await repo.incidenciasSoporte(estado: _filtroEstado)
          : await repo.incidenciasPropias();
      if (mounted) {
        setState(() {
          _incidencias = datos
              .whereType<Map>()
              .map((fila) => Map<String, dynamic>.from(fila))
              .toList();
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reportar() async {
    final controlador = TextEditingController();
    final descripcion = await showDialog<String>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Reportar incidencia'),
        content: TextField(
          controller: controlador,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: '¿Qué ocurrió?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(controlador.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controlador.dispose();
    if (descripcion == null || descripcion.length < 10) return;
    try {
      await ref.read(repositorioAdminProvider).reportarIncidencia(descripcion);
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidencia registrada. Soporte la revisará.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    }
  }

  Future<void> _gestionar(Map<String, dynamic> incidencia) async {
    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _DialogoGestion(incidencia: incidencia),
    );
    if (resultado == null) return;
    try {
      await ref.read(repositorioAdminProvider).actualizarIncidencia(
            '${incidencia['id']}',
            estado: '${resultado['estado']}',
            resolucion: resultado['resolucion'],
          );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_esSoporte ? 'Gestión de incidencias' : 'Mis incidencias'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: _esSoporte
          ? null
          : FloatingActionButton.extended(
              onPressed: _reportar,
              icon: const Icon(Icons.report_outlined),
              label: const Text('Reportar'),
            ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_esSoporte)
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Todas'),
                    selected: _filtroEstado == null,
                    onSelected: (_) {
                      setState(() => _filtroEstado = null);
                      _cargar();
                    },
                  ),
                  for (final estado in const ['ABIERTA', 'EN_PROCESO', 'RESUELTA', 'CERRADA'])
                    ChoiceChip(
                      label: Text(estado),
                      selected: _filtroEstado == estado,
                      onSelected: (_) {
                        setState(() => _filtroEstado = estado);
                        _cargar();
                      },
                    ),
                ],
              ),
            const SizedBox(height: 8),
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
            if (!_cargando && _error == null && _incidencias.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No hay incidencias para mostrar.'),
              ),
            for (final incidencia in _incidencias)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    switch ('${incidencia['estado']}') {
                      'RESUELTA' || 'CERRADA' => Icons.check_circle_outline,
                      'EN_PROCESO' => Icons.autorenew,
                      _ => Icons.error_outline,
                    },
                  ),
                  title: Text('${incidencia['descripcion']}'),
                  subtitle: Text(
                    '${incidencia['estado']} · ${incidencia['usuario']}'
                    '${incidencia['resolucion'] == null ? '' : '\nResolución: ${incidencia['resolucion']}'}',
                  ),
                  isThreeLine: incidencia['resolucion'] != null,
                  trailing: _esSoporte ? const Icon(Icons.chevron_right) : null,
                  onTap: _esSoporte ? () => _gestionar(incidencia) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialogoGestion extends StatefulWidget {
  const _DialogoGestion({required this.incidencia});

  final Map<String, dynamic> incidencia;

  @override
  State<_DialogoGestion> createState() => _DialogoGestionState();
}

class _DialogoGestionState extends State<_DialogoGestion> {
  late String _estado = '${widget.incidencia['estado']}';
  late final TextEditingController _resolucion =
      TextEditingController(text: '${widget.incidencia['resolucion'] ?? ''}');

  @override
  void dispose() {
    _resolucion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gestionar incidencia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.incidencia['descripcion']}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _estado,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'ABIERTA', child: Text('Abierta')),
                DropdownMenuItem(value: 'EN_PROCESO', child: Text('En proceso')),
                DropdownMenuItem(value: 'RESUELTA', child: Text('Resuelta')),
                DropdownMenuItem(value: 'CERRADA', child: Text('Cerrada')),
              ],
              onChanged: (valor) => setState(() => _estado = valor ?? _estado),
            ),
            TextField(
              controller: _resolucion,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Resolución (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'estado': _estado,
            'resolucion': _resolucion.text.trim(),
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
