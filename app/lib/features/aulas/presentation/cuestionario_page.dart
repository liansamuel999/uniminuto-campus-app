import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Cuestionario de una actividad: opciones y envío único con autocalificación (§6.4).
class CuestionarioPage extends ConsumerStatefulWidget {
  const CuestionarioPage({super.key, required this.actividadId, required this.titulo});

  final String actividadId;
  final String titulo;

  @override
  ConsumerState<CuestionarioPage> createState() => _CuestionarioPageState();
}

class _CuestionarioPageState extends ConsumerState<CuestionarioPage> {
  Map<String, dynamic>? _cuestionario;
  final Map<String, String> _seleccion = {};
  bool _cargando = true;
  bool _enviando = false;
  String? _error;
  int? _puntaje;

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
      final datos = await ref
          .read(apiClientProvider)
          .getJson('/cuestionarios/${widget.actividadId}')
          .timeout(const Duration(seconds: 12));
      if (mounted) setState(() => _cuestionario = datos);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el cuestionario.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _enviar() async {
    final preguntas = (_cuestionario?['preguntas'] as List<dynamic>? ?? const []);
    if (_seleccion.length < preguntas.length) {
      setState(() => _error = 'Responde todas las preguntas antes de enviar.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final respuesta = await ref.read(apiClientProvider).postJson(
        '/cuestionarios/${widget.actividadId}/intentos',
        cuerpo: {
          'respuestas': {
            for (final entrada in _seleccion.entries) entrada.key: [entrada.value],
          },
        },
      );
      if (!mounted) return;
      setState(() => _puntaje = (respuesta['puntaje'] as num?)?.round());
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preguntas = (_cuestionario?['preguntas'] as List<dynamic>? ?? const []);
    final yaRespondido = _cuestionario?['yaRespondido'] == true;

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!),
                  ),
                if (_puntaje != null)
                  Card(
                    color: const Color(0xFFE3F5E8),
                    child: ListTile(
                      leading: const Icon(Icons.check_circle, color: Color(0xFF1E7B3C)),
                      title: Text(
                        'Nota obtenida: $_puntaje',
                        style: const TextStyle(color: Color(0xFF1E7B3C), fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (yaRespondido && _puntaje == null)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Ya respondiste este cuestionario. Solo se permite un intento.'),
                    ),
                  ),
                for (var indice = 0; indice < preguntas.length; indice += 1)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                            child: Text(
                              '${indice + 1}. ${preguntas[indice]['enunciado']}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          for (final opcion in (preguntas[indice]['opciones'] as List<dynamic>? ?? const []))
                            RadioListTile<String>(
                              dense: true,
                              value: '${opcion['id']}',
                              groupValue: _seleccion['${preguntas[indice]['id']}'],
                              title: Text('${opcion['texto']}'),
                              onChanged: (_puntaje != null || yaRespondido)
                                  ? null
                                  : (valor) => setState(
                                        () => _seleccion['${preguntas[indice]['id']}'] = valor ?? '',
                                      ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_puntaje == null && !yaRespondido)
                  FilledButton.icon(
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: const Text('Enviar cuestionario'),
                  ),
              ],
            ),
    );
  }
}
