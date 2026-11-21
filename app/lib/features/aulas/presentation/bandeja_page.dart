import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Bandeja interna: anuncios importantes del aula y mensajes entre estudiantes y docentes.
class BandejaPage extends ConsumerStatefulWidget {
  const BandejaPage({super.key});

  @override
  ConsumerState<BandejaPage> createState() => _BandejaPageState();
}

class _BandejaPageState extends ConsumerState<BandejaPage> {
  List<Map<String, dynamic>> _anuncios = const [];
  List<Map<String, dynamic>> _recibidos = const [];
  List<Map<String, dynamic>> _enviados = const [];
  List<Map<String, dynamic>> _contactos = const [];
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
      final api = ref.read(apiClientProvider);
      final resultados = await Future.wait([
        api.getList('/correos-simulados'),
        api.getJson('/mensajes'),
        api.getList('/mensajes/contactos'),
      ]);
      final mensajes = resultados[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _anuncios = _mapas(resultados[0] as List<dynamic>);
        _recibidos = _mapas((mensajes['recibidos'] as List<dynamic>?) ?? const []);
        _enviados = _mapas((mensajes['enviados'] as List<dynamic>?) ?? const []);
        _contactos = _mapas(resultados[2] as List<dynamic>);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la bandeja.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static List<Map<String, dynamic>> _mapas(List<dynamic> datos) =>
      datos.whereType<Map>().map((fila) => Map<String, dynamic>.from(fila)).toList();

  Future<void> _marcarLeido(Map<String, dynamic> mensaje) async {
    if (mensaje['leido'] == true) return;
    try {
      await ref.read(apiClientProvider).putJson('/mensajes/${mensaje['id']}/leido');
      await _cargar();
    } catch (_) {
      // La lectura no debe bloquear la pantalla; se reintenta al refrescar.
    }
  }

  Future<void> _escribir() async {
    if (_contactos.isEmpty) {
      _aviso('No hay contactos de tus cursos para escribir.');
      return;
    }
    String? destinatarioId;
    final asunto = TextEditingController();
    final cuerpo = TextEditingController();
    final enviado = await showDialog<bool>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, setEstado) => AlertDialog(
          title: const Text('Nuevo mensaje'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: destinatarioId,
                  decoration: const InputDecoration(labelText: 'Destinatario'),
                  items: [
                    for (final contacto in _contactos)
                      DropdownMenuItem(
                        value: '${contacto['id']}',
                        child: Text(
                          '${contacto['nombre']} · ${contacto['rol']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (valor) => setEstado(() => destinatarioId = valor),
                ),
                TextField(
                  controller: asunto,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Asunto'),
                ),
                TextField(
                  controller: cuerpo,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Mensaje'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(contexto).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (destinatarioId == null || asunto.text.trim().isEmpty || cuerpo.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(contexto).pop(true);
              },
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (enviado != true || !mounted) {
      asunto.dispose();
      cuerpo.dispose();
      return;
    }
    try {
      await ref.read(apiClientProvider).postJson('/mensajes', cuerpo: {
        'destinatarioId': destinatarioId,
        'asunto': asunto.text.trim(),
        'cuerpo': cuerpo.text.trim(),
      });
      if (mounted) {
        _aviso('Mensaje enviado.');
        await _cargar();
      }
    } on ApiException catch (error) {
      if (mounted) _aviso(error.mensaje);
    } finally {
      asunto.dispose();
      cuerpo.dispose();
    }
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandeja'),
        actions: [
          IconButton(
            tooltip: 'Nuevo mensaje',
            onPressed: _cargando ? null : _escribir,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
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
            if (!_cargando && _recibidos.isEmpty && _anuncios.isEmpty && _enviados.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(Icons.mail_outline, size: 44),
                    SizedBox(height: 10),
                    Text(
                      'No tienes mensajes todavía. Usa el botón de escribir para contactar '
                      'a un docente o compañero de tus cursos.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            if (_recibidos.isNotEmpty) ...[
              Text('Mensajes recibidos', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final mensaje in _recibidos) _tarjetaMensaje(mensaje, recibido: true),
              const SizedBox(height: 14),
            ],
            if (_anuncios.isNotEmpty) ...[
              Text('Anuncios de tus cursos', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final anuncio in _anuncios) _tarjetaAnuncio(anuncio),
              const SizedBox(height: 14),
            ],
            if (_enviados.isNotEmpty) ...[
              Text('Mensajes enviados', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final mensaje in _enviados) _tarjetaMensaje(mensaje, recibido: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaMensaje(Map<String, dynamic> mensaje, {required bool recibido}) {
    final leido = mensaje['leido'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          leido ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
          color: leido ? null : Theme.of(context).colorScheme.primary,
        ),
        title: Text('${mensaje['asunto']}'),
        subtitle: Text(
          'De ${mensaje['remitente']} para ${mensaje['destinatario']}\n'
          '${mensaje['cuerpo']}\n${_fechaCorta('${mensaje['creadoEn']}')}',
        ),
        isThreeLine: true,
        onTap: recibido ? () => _marcarLeido(mensaje) : null,
      ),
    );
  }

  Widget _tarjetaAnuncio(Map<String, dynamic> anuncio) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${anuncio['asunto']}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${anuncio['cuerpo']}'),
            const SizedBox(height: 8),
            Text(
              'Anuncio · ${_fechaCorta('${anuncio['creadoEn']}')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _fechaCorta(String iso) {
  final fecha = DateTime.tryParse(iso)?.toLocal();
  if (fecha == null) return iso;
  return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} '
      '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
}
