import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formato.dart';

/// Compañeros y docente del curso, con opción de escribirles.
class ParticipantesPage extends ConsumerStatefulWidget {
  const ParticipantesPage({super.key, required this.aulaId, this.esDocente = false});

  final String aulaId;
  final bool esDocente;

  @override
  ConsumerState<ParticipantesPage> createState() => _ParticipantesPageState();
}

class _ParticipantesPageState extends ConsumerState<ParticipantesPage> {
  List<Map<String, dynamic>> _participantes = const [];
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
      final datos = await ref.read(repositorioAcademicoProvider).participantes(widget.aulaId);
      if (mounted) {
        setState(() {
          _participantes = datos
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

  @override
  Widget build(BuildContext context) {
    final docentes = _participantes.where((p) => '${p['rol']}' == 'DOCENTE').toList();
    final estudiantes = _participantes.where((p) => '${p['rol']}' == 'ESTUDIANTE').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Participantes')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_cargando && docentes.isNotEmpty) ...[
              Text('Docente', style: Theme.of(context).textTheme.titleSmall),
              for (final docente in docentes) _fila(context, docente, esDocente: true),
              const SizedBox(height: 16),
            ],
            if (!_cargando && estudiantes.isNotEmpty) ...[
              Text(
                'Compañeros (${estudiantes.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final estudiante in estudiantes) _fila(context, estudiante),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Map<String, dynamic> persona, {bool esDocente = false}) {
    final iniciales = '${persona['nombre']}'
        .split(' ')
        .where((parte) => parte.isNotEmpty)
        .take(2)
        .map((parte) => parte[0])
        .join()
        .toUpperCase();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: esDocente
              ? Theme.of(context).colorScheme.tertiaryContainer
              : Theme.of(context).colorScheme.primaryContainer,
          child: Text(iniciales),
        ),
        title: Text('${persona['nombre']}'),
        subtitle: Text('${persona['correo']}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _verPersona(context, persona),
      ),
    );
  }

  Future<void> _verPersona(BuildContext context, Map<String, dynamic> persona) async {
    final correo = '${persona['correo']}';
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('${persona['nombre']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rol: ${persona['rol']}'),
            const SizedBox(height: 4),
            Text('Correo: $correo'),
            if (persona['codigoInstitucional'] != null)
              Text('Código: ${persona['codigoInstitucional']}'),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: correo));
              if (contexto.mounted) {
                ScaffoldMessenger.of(contexto).showSnackBar(
                  const SnackBar(content: Text('Correo copiado al portapapeles.')),
                );
              }
            },
            child: const Text('Copiar correo'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(contexto).pop();
              await abrirEnlace(context, 'mailto:$correo');
            },
            child: const Text('Escribir'),
          ),
        ],
      ),
    );
  }
}
