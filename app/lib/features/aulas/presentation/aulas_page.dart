import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/formato.dart';
import 'aula_detalle_page.dart';
import 'curso_grupos_page.dart';

/// Un curso se muestra por su **código de asignatura** (no por cada grupo). Un docente con
/// IS-201 grupos 01 y 02 ve un solo curso y dentro elige el grupo.
class _CursoAgrupado {
  _CursoAgrupado({
    required this.codigo,
    required this.periodo,
    required this.asignatura,
    required this.aulas,
  });

  final String codigo;
  final String periodo;
  final String asignatura;
  final List<Map<String, dynamic>> aulas;

  String get docente {
    final docentes = aulas.map((aula) => '${aula['docente'] ?? ''}').toSet()..remove('');
    return docentes.length == 1 ? docentes.first : (docentes.isEmpty ? 'Sin asignar' : 'Varios');
  }

  bool get esDocente => aulas.any((aula) => '${aula['rolEnAula']}' == 'DOCENTE');
}

/// Lista de cursos del usuario con la sección «Próximas entregas» al inicio (solo estudiantes).
class AulasPage extends ConsumerStatefulWidget {
  const AulasPage({super.key});

  @override
  ConsumerState<AulasPage> createState() => _AulasPageState();
}

class _AulasPageState extends ConsumerState<AulasPage> {
  List<Map<String, dynamic>> _aulas = const [];
  List<_CursoAgrupado> _cursos = const [];
  List<Map<String, dynamic>> _proximas = const [];
  bool _cargando = true;
  String? _error;

  bool get _esEstudiante =>
      ref.read(sesionProvider).valueOrNull?.roles.contains('ESTUDIANTE') ?? false;

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
      final esEstudiante = _esEstudiante;
      final resultados = await Future.wait([
        repo.aulas(),
        if (esEstudiante) repo.proximasActividades(),
      ]);
      if (!mounted) return;
      setState(() {
        _aulas = _mapas(resultados[0]);
        _cursos = _agruparCursos(_aulas);
        // La API ya excluye entregas e intentos hechos; se ordena por fecha y se limita la lista.
        _proximas = esEstudiante ? _mapas(resultados[1]).take(6).toList() : const [];
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

  static List<_CursoAgrupado> _agruparCursos(List<Map<String, dynamic>> aulas) {
    final mapa = <String, _CursoAgrupado>{};
    for (final aula in aulas) {
      final codigo = '${aula['codigo'] ?? ''}';
      final periodo = '${aula['periodo'] ?? ''}';
      final clave = '$codigo|$periodo';
      final existente = mapa[clave];
      if (existente == null) {
        mapa[clave] = _CursoAgrupado(
          codigo: codigo,
          periodo: periodo,
          asignatura: '${aula['asignatura'] ?? ''}',
          aulas: [aula],
        );
      } else {
        existente.aulas.add(aula);
      }
    }
    return mapa.values.toList()
      ..sort((a, b) => a.asignatura.compareTo(b.asignatura));
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final esEstudiante = _esEstudiante;
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
            if (esEstudiante) _seccionProximas(context),
            Text(
              'Mis cursos',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (!_cargando && _cursos.isEmpty) const Text('No tienes cursos asignados.'),
            for (final curso in _cursos) _tarjetaCurso(context, curso),
          ],
        ),
      ),
    );
  }

  Widget _seccionProximas(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Próximas entregas',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (!_cargando && _proximas.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colores.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.task_alt),
                SizedBox(width: 8),
                Expanded(child: Text('No tienes actividades pendientes por entregar.')),
              ],
            ),
          ),
        for (final actividad in _proximas) _tarjetaProxima(context, actividad),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Tarjeta de tamaño fijo: los títulos y fechas largos se recortan para que no cambie el
  /// espaciado entre cursos (corrección de la muestra).
  Widget _tarjetaProxima(BuildContext context, Map<String, dynamic> actividad) {
    final cierre = DateTime.tryParse('${actividad['cierraEn']}');
    final tipo = '${actividad['tipo']}';
    final colores = Theme.of(context).colorScheme;
    final icono = switch (tipo) {
      'TAREA' => Icons.assignment_outlined,
      'CUESTIONARIO' => Icons.quiz_outlined,
      _ => Icons.forum_outlined,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AulaDetallePage(
              aulaId: '${actividad['aulaId']}',
              titulo: '${actividad['asignatura']}',
              actividadInicialId: '${actividad['actividadId']}',
            ),
          ),
        ),
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(icono, color: colores.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${actividad['titulo']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${actividad['asignatura']} · '
                        '${cierre == null ? 'sin fecha límite' : 'vence en ${tiempoRestante(cierre)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCurso(BuildContext context, _CursoAgrupado curso) {
    final colores = Theme.of(context).colorScheme;
    final unico = curso.aulas.length == 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (unico) {
            final aula = curso.aulas.first;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AulaDetallePage(aulaId: '${aula['id']}', titulo: curso.asignatura),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CursoGruposPage(
                  asignatura: curso.asignatura,
                  codigo: curso.codigo,
                  periodo: curso.periodo,
                  aulas: curso.aulas,
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colores.primaryContainer,
                child: Icon(Icons.school_outlined, color: colores.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      curso.asignatura,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${curso.codigo} · ${curso.periodo} · '
                      '${curso.aulas.length} grupo(s) · Docente: ${curso.docente}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (curso.esDocente)
                const Chip(label: Text('Docente'), visualDensity: VisualDensity.compact)
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
