import 'package:flutter/material.dart';

import 'aula_detalle_page.dart';

/// Grupos de un mismo curso (misma asignatura/código).
///
/// El curso se muestra una sola vez por código; aquí el docente elige el grupo con el que quiere
/// trabajar (el grupo determina estudiantes, entregas y notas).
class CursoGruposPage extends StatelessWidget {
  const CursoGruposPage({
    super.key,
    required this.asignatura,
    required this.codigo,
    required this.periodo,
    required this.aulas,
  });

  final String asignatura;
  final String codigo;
  final String periodo;
  final List<Map<String, dynamic>> aulas;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(asignatura, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$codigo · $periodo',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '${aulas.length} grupos de este curso',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final aula in aulas)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colores.primaryContainer,
                  child: Text('${aula['grupo']}'),
                ),
                title: Text('Grupo ${aula['grupo']}'),
                subtitle: Text('Docente: ${aula['docente'] ?? 'Sin asignar'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AulaDetallePage(
                      aulaId: '${aula['id']}',
                      titulo: asignatura,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
