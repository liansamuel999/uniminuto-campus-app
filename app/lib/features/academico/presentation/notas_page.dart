import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../aulas/presentation/calificaciones_curso_page.dart';

/// Notas del periodo.
///
/// - Estudiante: **solo** la definitiva del periodo y la nota de cada corte. La definitiva se
///   muestra como «en curso» hasta que cierran todas las actividades de todos los cortes, para
///   que no cambie a mitad de semestre (D-44 y aclaración del cliente).
/// - Docente: «Resumen de notas» con el avance de calificación por curso.
class NotasPage extends ConsumerStatefulWidget {
  const NotasPage({super.key});

  @override
  ConsumerState<NotasPage> createState() => _NotasPageState();
}

class _NotasPageState extends ConsumerState<NotasPage> {
  List<Map<String, dynamic>> _notas = const [];
  List<Map<String, dynamic>> _resumenCursos = const [];
  bool _cargando = true;
  bool _esDocente = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final sesion = ref.read(sesionProvider).valueOrNull;
    _esDocente = sesion?.roles.contains('DOCENTE') ?? false;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_esDocente) {
        await _cargarResumenDocente();
      } else {
        final (notas, _) = await ref.read(repositorioAcademicoProvider).notas();
        if (mounted) {
          setState(() {
            _notas = notas
                .whereType<Map>()
                .map((fila) => Map<String, dynamic>.from(fila))
                .toList();
          });
        }
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las notas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarResumenDocente() async {
    final repo = ref.read(repositorioAcademicoProvider);
    final aulas = await repo.aulas();
    final api = ref.read(apiClientProvider);
    final resumen = <Map<String, dynamic>>[];
    for (final aula in aulas.whereType<Map>()) {
      if ('${aula['rolEnAula']}' != 'DOCENTE') continue;
      final filas = await api.getList('/aulas/${aula['id']}/calificaciones');
      final mapas = filas.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();
      final calificadas = mapas.where((fila) => fila['nota'] != null).toList();
      final promedio = calificadas.isEmpty
          ? null
          : calificadas.map((fila) => (fila['nota'] as num).toDouble()).reduce((a, b) => a + b) /
              calificadas.length;
      resumen.add({
        'aulaId': '${aula['id']}',
        'asignatura': '${aula['asignatura']}',
        'codigo': '${aula['codigo']}',
        'grupo': '${aula['grupo']}',
        'actividades': mapas.map((fila) => '${fila['actividadId']}').toSet().length,
        'notas': mapas.length,
        'calificadas': calificadas.length,
        'promedio': promedio,
      });
    }
    if (mounted) {
      setState(() {
        _resumenCursos = resumen;
        _esDocente = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_esDocente ? 'Resumen de notas' : 'Mis notas'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: colores.error)),
            if (!_cargando && _error == null && !_esDocente && _notas.isEmpty)
              const Text('Todavía no hay notas para el periodo activo.'),
            if (_esDocente)
              for (final curso in _resumenCursos) _tarjetaDocente(context, curso)
            else
              for (final asignatura in _notas) _tarjetaEstudiante(context, asignatura),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaEstudiante(BuildContext context, Map<String, dynamic> asignatura) {
    final colores = Theme.of(context).colorScheme;
    final cortes = (asignatura['cortes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((corte) => Map<String, dynamic>.from(corte))
        .toList();
    final publicada = asignatura['definitivaPublicada'] == true;
    final definitiva = (asignatura['definitiva'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${asignatura['asignatura']}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${asignatura['codigo']}',
                        style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      publicada ? definitiva.toStringAsFixed(2) : 'En curso',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: publicada
                                ? (definitiva >= 3 ? const Color(0xFF1E7A3C) : colores.error)
                                : colores.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      publicada ? 'Definitiva' : 'Definitiva al cierre',
                      style: TextStyle(fontSize: 11, color: colores.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final corte in cortes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Text('Corte ${corte['numero']} (${corte['peso']}%)'),
                    if (corte['cerrado'] != true)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('· en curso', style: TextStyle(fontSize: 11, color: colores.primary)),
                      ),
                    const Spacer(),
                    Text(
                      corte['nota'] == null ? 'Sin nota' : (corte['nota'] as num).toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaDocente(BuildContext context, Map<String, dynamic> curso) {
    final promedio = curso['promedio'] as double?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined),
        title: Text('${curso['asignatura']}'),
        subtitle: Text(
          '${curso['codigo']} · Grupo ${curso['grupo']}\n'
          '${curso['calificadas']} de ${curso['notas']} notas puestas'
          '${promedio == null ? '' : ' · promedio ${promedio.toStringAsFixed(2)}'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CalificacionesCursoPage(aulaId: '${curso['aulaId']}', esDocente: true),
          ),
        ),
      ),
    );
  }
}
