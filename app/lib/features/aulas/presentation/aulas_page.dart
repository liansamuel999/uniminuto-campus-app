import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/formato.dart';
import 'aula_detalle_page.dart';

/// Lista de cursos del usuario. Cada curso se identifica por su **código de curso** (NRC), no por
/// un número de grupo: dos ofertas de la misma asignatura son dos cursos con códigos distintos.
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
  final PageController _paginaProximas = PageController();
  int _indiceProximas = 0;

  @override
  void dispose() {
    _paginaProximas.dispose();
    super.dispose();
  }

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
        // La API ya excluye entregas e intentos hechos; se muestran de 5 en 5 con navegación.
        _proximas = esEstudiante ? _mapas(resultados[1]) : const [];
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
            if (!_cargando && _aulas.isEmpty) const Text('No tienes cursos asignados.'),
            for (final aula in _aulas) _tarjetaCurso(context, aula),
          ],
        ),
      ),
    );
  }

  Widget _seccionProximas(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final paginas = (_proximas.length / 5).ceil();
    final visibles = _proximas.length < 5 ? _proximas.length : 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Próximas entregas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (paginas > 1)
              Text(
                '${_indiceProximas + 1}/$paginas',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
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
        if (_proximas.isNotEmpty)
          SizedBox(
            height: visibles * 76.0,
            child: PageView.builder(
              controller: _paginaProximas,
              itemCount: paginas,
              onPageChanged: (indice) => setState(() => _indiceProximas = indice),
              itemBuilder: (contexto, pagina) {
                final desde = pagina * 5;
                final hasta = desde + 5 > _proximas.length ? _proximas.length : desde + 5;
                return Column(
                  children: [
                    for (final actividad in _proximas.sublist(desde, hasta))
                      _tarjetaProxima(contexto, actividad),
                  ],
                );
              },
            ),
          ),
        if (paginas > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _indiceProximas == 0
                    ? null
                    : () => _paginaProximas.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                icon: const Icon(Icons.chevron_left),
              ),
              for (var indice = 0; indice < paginas; indice += 1)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: indice == _indiceProximas ? colores.primary : colores.outlineVariant,
                  ),
                ),
              IconButton(
                onPressed: _indiceProximas >= paginas - 1
                    ? null
                    : () => _paginaProximas.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Tarjeta de tamaño fijo: los títulos y fechas largos se recortan para que no cambie el
  /// espaciado entre cursos.
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

  Widget _tarjetaCurso(BuildContext context, Map<String, dynamic> aula) {
    final colores = Theme.of(context).colorScheme;
    final esDocente = '${aula['rolEnAula']}' == 'DOCENTE';
    final codigoCurso = '${aula['codigoCurso'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AulaDetallePage(aulaId: '${aula['id']}', titulo: '${aula['asignatura']}'),
          ),
        ),
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
                      '${aula['asignatura']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Código de curso $codigoCurso · ${aula['periodo']} · '
                      'Docente: ${aula['docente'] ?? 'Sin asignar'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (esDocente)
                      Text(
                        '${aula['codigo']} · ${aula['nombre']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              if (esDocente)
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
