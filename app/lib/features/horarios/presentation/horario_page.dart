import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Horario semanal con la ubicación del salón (§4.3, Fase 4) y caché offline (D-40).
class HorarioPage extends ConsumerStatefulWidget {
  const HorarioPage({super.key});

  @override
  ConsumerState<HorarioPage> createState() => _HorarioPageState();
}

class _HorarioPageState extends ConsumerState<HorarioPage> {
  List<dynamic> _bloques = const [];
  bool _cargando = true;
  bool _desdeCache = false;
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
      final (bloques, desdeCache) = await ref.read(repositorioAcademicoProvider).horario();
      if (mounted) {
        setState(() {
          _bloques = bloques;
          _desdeCache = desdeCache;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el horario.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final periodo = _bloques.isEmpty
        ? null
        : (_bloques.first is Map ? (_bloques.first as Map)['periodo'] : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi horario'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_desdeCache)
              _Banner(
                icono: Icons.cloud_off_outlined,
                texto: 'Sin conexión: mostrando el horario guardado en el dispositivo.',
                color: colores.tertiaryContainer,
              ),
            if (_error != null)
              _Banner(icono: Icons.error_outline, texto: _error!, color: colores.errorContainer),
            if (periodo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Periodo $periodo', style: Theme.of(context).textTheme.titleSmall),
              ),
            if (!_cargando && _error == null && _bloques.isEmpty)
              const Text('Todavía no tienes horario asignado para el periodo activo.'),
            for (var dia = 1; dia <= 7; dia += 1) ..._bloquesDelDia(context, dia),
          ],
        ),
      ),
    );
  }

  List<Widget> _bloquesDelDia(BuildContext context, int dia) {
    final bloques = _bloques
        .whereType<Map>()
        .where((bloque) => (bloque['dia'] as num?)?.toInt() == dia)
        .toList();
    if (bloques.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          '${bloques.first['diaNombre']}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      for (final bloque in bloques) _tarjetaBloque(context, bloque),
    ];
  }

  Widget _tarjetaBloque(BuildContext context, Map<dynamic, dynamic> bloque) {
    final salon = bloque['salon'] is Map ? bloque['salon'] as Map : const {};
    final docente = bloque['docente'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${bloque['horaInicio']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${bloque['horaFin']}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        title: Text('${bloque['asignatura']}'),
        subtitle: Text(
          '${bloque['codigo']} · Grupo ${bloque['grupo']}\n'
          'Salón ${salon['codigo'] ?? '—'} · ${salon['edificio'] ?? '—'}, piso ${salon['piso'] ?? '—'}'
          '${docente == null ? '' : '\nDocente: $docente'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.meeting_room_outlined),
        onTap: () => _detalleSalon(context, bloque),
      ),
    );
  }

  void _detalleSalon(BuildContext context, Map<dynamic, dynamic> bloque) {
    final salon = bloque['salon'] is Map ? bloque['salon'] as Map : const {};
    showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('Salón ${salon['codigo'] ?? '—'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${bloque['asignatura']} · Grupo ${bloque['grupo']}'),
            const SizedBox(height: 8),
            Text('${salon['tipo'] ?? 'AULA'} · capacidad ${salon['capacidad'] ?? '—'}'),
            Text('${salon['edificio'] ?? '—'} (${salon['edificioCodigo'] ?? '—'}), piso ${salon['piso'] ?? '—'}'),
            Text('Sede ${salon['sede'] ?? 'CALLE_80'}'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(contexto).pop(), child: const Text('Cerrar'))],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icono, required this.texto, required this.color});

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icono, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
