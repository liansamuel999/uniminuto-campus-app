import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/carnet_providers.dart';
import '../domain/verificador.dart';

/// Modo validador (§6.1): valida el QR sin red y encola el evento de auditoría.
class ValidadorPage extends ConsumerStatefulWidget {
  const ValidadorPage({super.key});

  @override
  ConsumerState<ValidadorPage> createState() => _ValidadorPageState();
}

class _ValidadorPageState extends ConsumerState<ValidadorPage> {
  final _texto = TextEditingController();
  ResultadoValidacion? _resultado;
  bool _validando = false;
  bool _escaneando = false;
  bool _sincronizando = false;
  String? _estadoSync;
  List<Map<String, dynamic>> _historial = const [];

  @override
  void initState() {
    super.initState();
    _historial = ref.read(historialValidacionesProvider).recientes();
    _sincronizar();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _validar(String qr) async {
    if (qr.trim().isEmpty || _validando) return;
    setState(() {
      _validando = true;
      _resultado = null;
    });
    try {
      final verificador = await ref.read(verificadorCarnetProvider.future);
      final resultado = await verificador.validar(qr);
      final ahora = DateTime.now();
      await ref.read(historialValidacionesProvider).agregar(resultado, cuando: ahora);
      if (resultado.carnetId != null) {
        await ref.read(colaEventosProvider).agregar(resultado, cuando: ahora);
      }
      if (!mounted) return;
      setState(() {
        _resultado = resultado;
        _historial = ref.read(historialValidacionesProvider).recientes();
        _escaneando = false;
      });
      await _subirPendientes();
    } catch (_) {
      if (mounted) setState(() => _resultado = const ResultadoValidacion(motivo: MotivoValidacion.formatoInvalido));
    } finally {
      if (mounted) setState(() => _validando = false);
    }
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() {
      _sincronizando = true;
      _estadoSync = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      try {
        final revocaciones = await api.getJson('/acceso/revocaciones');
        final carnets = (revocaciones['carnets'] as List<dynamic>? ?? const []).map((e) => '$e').toList();
        await ref.read(listaRevocadosProvider).actualizar(
              carnets: carnets,
              version: (revocaciones['version'] as num?)?.toInt() ?? 0,
              actualizadoEn: DateTime.tryParse('${revocaciones['actualizadoEn']}'),
            );
      } on ApiException catch (error) {
        if (!error.esProhibido && !error.esSinRed) rethrow;
      }
      final subidos = await _subirPendientes();
      if (mounted) {
        setState(() {
          _estadoSync = 'Lista de revocación actualizada. Eventos pendientes subidos: $subidos.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _estadoSync = 'Sin conexión: ${error.mensaje}');
    } catch (_) {
      if (mounted) setState(() => _estadoSync = 'Sin conexión: los eventos quedan en cola.');
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<int> _subirPendientes() async {
    final cola = ref.read(colaEventosProvider);
    final pendientes = cola.pendientes().where((evento) => evento['carnetId'] != null).toList();
    if (pendientes.isEmpty) return 0;
    final lote = pendientes.take(100).toList();
    final api = ref.read(apiClientProvider);
    final respuesta = await api.postJson('/auditoria/accesos', cuerpo: {'eventos': lote});
    final insertados = (respuesta['insertados'] as num?)?.toInt() ?? 0;
    await cola.eliminar(lote.map((evento) => '${evento['id']}').toList());
    return insertados;
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo validador'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: _sincronizando ? null : _sincronizar,
            icon: _sincronizando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!kIsWeb) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: _escaneando
                          ? MobileScanner(
                              onDetect: (captura) {
                                final valor = captura.barcodes.firstOrNull?.rawValue;
                                if (valor != null) _validar(valor);
                              },
                            )
                          : Center(
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _escaneando = true),
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('Escanear QR con la cámara'),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _texto,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: kIsWeb ? 'Pega el texto del QR' : 'Texto del QR (alternativa a la cámara)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _validando ? null : () => _validar(_texto.text),
            icon: _validando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_outlined),
            label: Text(_validando ? 'Validando…' : 'Validar'),
          ),
          if (_resultado != null) ...[
            const SizedBox(height: 16),
            _ResultadoCard(resultado: _resultado!),
          ],
          if (_estadoSync != null) ...[
            const SizedBox(height: 12),
            Text(_estadoSync!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          Text('Historial reciente', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_historial.isEmpty)
            Text('Sin validaciones todavía.', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final evento in _historial.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  evento['permitido'] == true ? Icons.check_circle : Icons.cancel,
                  color: evento['permitido'] == true ? Colors.green : colores.error,
                ),
                title: Text('${evento['motivo']}'),
                subtitle: Text('${evento['cuando']}'),
              ),
        ],
      ),
    );
  }
}

class _ResultadoCard extends StatelessWidget {
  const _ResultadoCard({required this.resultado});

  final ResultadoValidacion resultado;

  @override
  Widget build(BuildContext context) {
    final permitido = resultado.permitido;
    final fondo = permitido ? const Color(0xFFE3F5E8) : const Color(0xFFFDE7E7);
    final color = permitido ? const Color(0xFF1E7B3C) : const Color(0xFFB3261E);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(permitido ? Icons.check_circle : Icons.cancel, size: 40, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permitido ? 'PERMITIDO' : 'DENEGADO',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
                ),
                Text(resultado.motivo.mensaje, style: TextStyle(color: color)),
                if (resultado.codigo != null)
                  Text('Carnet ${resultado.codigo}', style: Theme.of(context).textTheme.bodySmall),
                if (resultado.motivoCodigo != 'OK')
                  Text('Motivo: ${resultado.motivoCodigo}', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
