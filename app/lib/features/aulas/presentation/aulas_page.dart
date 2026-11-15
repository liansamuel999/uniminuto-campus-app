import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';
import 'aula_detalle_page.dart';

/// Lista de cursos del usuario con la sección «Próximas entregas» al inicio.
class AulasPage extends ConsumerStatefulWidget {
  const AulasPage({super.key});

  @override
  ConsumerState<AulasPage> createState() => _AulasPageState();
}

class _AulasPageState extends ConsumerState<AulasPage> {
  List<Map<String, dynamic>> _aulas = const [];
  List<Map<String, dynamic>> _proximas = const [];
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
      final repo = ref.read(repositorioAcademicoProvider);
      final resultados = await Future.wait([repo.aulas(), repo.proximasActividades()]);
      if (!mounted) return;
      setState(() {
        _aulas = _mapas(resultados[0]);
        _proximas = _mapas(resultados[1]).take(6).toList();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las aulas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static List<Map<String, dynamic>> _mapas(List<dynamic> datos) =>
      datos.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aulas virtuales'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            if (_proximas.isNotEmpty) ...[
              Text(
                'Próximas entregas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final actividad in _proximas) _tarjetaProxima(context, actividad),
              const SizedBox(height: 16),
            ],
            Text(
              'Mis cursos',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (!_cargando && _aulas.isEmpty) const Text('No tienes cursos asignados.'),
            for (final aula in _aulas) _tarjetaAula(context, aula),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaProxima(BuildContext context, Map<String, dynamic> actividad) {
    final cierre = DateTime.tryParse('${actividad['cierraEn']}');
    final tipo = '${actividad['tipo']}';
    final entregada = actividad['entregada'] == true;
    final colores = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(switch (tipo) {
          'TAREA' => Icons.assignment_outlined,
          'CUESTIONARIO' => Icons.quiz_outlined,
          _ => Icons.forum_outlined,
        }, color: colores.primary),
        title: Text('${actividad['titulo']}'),
        subtitle: Text(
          '${actividad['asignatura']} · ${cierre == null ? 'sin fecha límite' : 'vence en ${tiempoRestante(cierre)}'}'
          '${entregada ? ' · entregada' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AulaDetallePage(
              aulaId: '${actividad['aulaId']}',
              titulo: '${actividad['asignatura']}',
              actividadInicialId: '${actividad['actividadId']}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAula(BuildContext context, Map<String, dynamic> aula) {
    final colores = Theme.of(context).colorScheme;
    final esDocente = '${aula['rolEnAula']}' == 'DOCENTE';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colores.primaryContainer,
          child: Icon(Icons.school_outlined, color: colores.onPrimaryContainer),
        ),
        title: Text('${aula['asignatura']}'),
        subtitle: Text(
          '${aula['codigo']} · Grupo ${aula['grupo']} · ${aula['periodo']}\n'
          'Docente: ${aula['docente'] ?? 'Sin asignar'}',
        ),
        isThreeLine: true,
        trailing: esDocente
            ? const Chip(label: Text('Docente'), visualDensity: VisualDensity.compact)
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AulaDetallePage(aulaId: '${aula['id']}', titulo: '${aula['asignatura']}'),
          ),
        ),
      ),
    );
  }
}
