import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/carnet_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/security/device_keys.dart';
import '../../../core/widgets/aviso_muestra.dart';
import '../data/carnet_repository.dart';
import '../domain/carnet.dart';
import '../services/qr_service.dart';

/// Pantalla del carnet digital: datos, QR dinámico y código de barras (§6.1).
class CarnetPage extends ConsumerStatefulWidget {
  const CarnetPage({super.key});

  @override
  ConsumerState<CarnetPage> createState() => _CarnetPageState();
}

class _CarnetPageState extends ConsumerState<CarnetPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  ResumenCarnet? _resumen;
  ClaveDispositivo? _clave;
  ServicioQr? _servicio;
  String? _qr;
  int _segundos = 30;
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  String? _aviso;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  CarnetRepository get _repo => ref.read(carnetRepositoryProvider);

  Future<void> _inicializar() async {
    if (mounted) setState(() => _cargando = true);
    final repo = _repo;
    var resumen = repo.cargarLocal();
    final clave = await repo.claveGuardada();
    String? aviso;

    try {
      final remoto = await repo.sincronizar();
      if (remoto != null) resumen = remoto;
    } on ApiException catch (error) {
      aviso = 'Sin conexión con la API: se muestra la última copia guardada. '
          '(${error.codigo == 'SIN_RED' ? 'sin red' : error.mensaje})';
    } catch (_) {
      aviso = 'No se pudo actualizar el carnet; se usa la copia local.';
    }

    // Renovación anticipada si quedan menos de 7 días y hay red (§6.1).
    final certificado = resumen?.certificado;
    if (certificado != null && certificado.porVencer && resumen?.tieneDispositivo == true) {
      try {
        resumen = await repo.renovar();
        aviso = null;
      } catch (_) {
        aviso ??= 'Tu certificado está por vencer y no se pudo renovar. Conéctate a la red.';
      }
    }

    if (!mounted) return;
    setState(() {
      _resumen = resumen;
      _clave = clave;
      _cargando = false;
      _aviso = aviso;
      _error = null;
    });
    await _prepararQr();
  }

  Future<void> _prepararQr() async {
    _reloj?.cancel();
    final resumen = _resumen;
    final clave = _clave;
    final certificado = resumen?.certificado;

    if (resumen == null || clave == null || certificado == null || certificado.vencido) {
      if (mounted) setState(() => _qr = null);
      return;
    }

    _servicio = ServicioQr(carnet: resumen.carnet, certificado: certificado, clave: clave);
    await _refrescarQr();
    _reloj = Timer.periodic(const Duration(seconds: 1), (temporizador) {
      if (!mounted) return;
      if (_segundos <= 1) {
        _refrescarQr();
        return;
      }
      setState(() => _segundos -= 1);
    });
  }

  Future<void> _refrescarQr() async {
    final servicio = _servicio;
    if (servicio == null) return;
    try {
      final qr = await servicio.generar(DateTime.now());
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _segundos = ServicioQr.vigenciaToken.inSeconds;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo generar el QR con la clave del dispositivo');
    }
  }

  Future<void> _vincular() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final nombre = defaultTargetPlatform == TargetPlatform.android
          ? 'Teléfono Android'
          : defaultTargetPlatform == TargetPlatform.iOS
              ? 'iPhone'
              : 'Navegador web';
      final resumen = await _repo.vincular(nombre);
      final clave = await _repo.claveGuardada();
      if (!mounted) return;
      setState(() {
        _resumen = resumen;
        _clave = clave;
        _aviso = null;
      });
      await _prepararQr();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _revocar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Revocar este dispositivo'),
        content: const Text(
          'El QR dejará de funcionar en este dispositivo y deberás vincularlo de nuevo. '
          'La revocación del carnet se sincroniza con los validadores cuando recuperen red.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Revocar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _ocupado = true);
    try {
      await _repo.revocar();
      if (!mounted) return;
      setState(() {
        _resumen = null;
        _clave = null;
        _qr = null;
      });
      _reloj?.cancel();
      await _inicializar();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carnet'),
        actions: [
          if (_resumen?.tieneDispositivo == true)
            IconButton(
              tooltip: 'Revocar dispositivo',
              onPressed: _ocupado ? null : _revocar,
              icon: const Icon(Icons.phonelink_erase_outlined),
            ),
          IconButton(tooltip: 'Actualizar', onPressed: _ocupado ? null : _inicializar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _inicializar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (_error != null) _Banner(texto: _error!, color: Theme.of(context).colorScheme.errorContainer),
            if (_aviso != null) _Banner(texto: _aviso!, color: Theme.of(context).colorScheme.tertiaryContainer),
            if (!_cargando && _resumen != null) _tarjetaCarnet(context, sesion),
            if (!_cargando && _resumen == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay un carnet asociado a tu cuenta.'),
                ),
              ),
            if (!_cargando && _resumen != null && !_resumen!.tieneDispositivo) ...[
              const SizedBox(height: 16),
              _tarjetaVinculacion(context),
            ],
            if (!_cargando && _resumen?.tieneDispositivo == true && _resumen?.certificado != null) ...[
              const SizedBox(height: 16),
              _tarjetaQr(context),
              const SizedBox(height: 12),
              const AvisoMuestra(compacto: true),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaCarnet(BuildContext context, Sesion? sesion) {
    final perfil = sesion?.perfil;
    final carnet = _resumen!.carnet;
    final colores = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colores.primaryContainer,
                  child: Icon(Icons.person, color: colores.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        perfil?.nombreCompleto ?? 'Estudiante',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(perfil?.codigoInstitucional ?? carnet.codigoBarras,
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(perfil?.programa?.nombre ?? 'Sin programa',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant)),
                    ],
                  ),
                ),
                Chip(
                  label: Text(carnet.estado),
                  backgroundColor: carnet.activo ? colores.primaryContainer : colores.errorContainer,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Vigente hasta ${_fecha(carnet.vigenteHasta)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
            ),
            if (_resumen!.dispositivoNombre != null)
              Text(
                'Dispositivo: ${_resumen!.dispositivoNombre}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaVinculacion(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vincula este dispositivo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            const Text(
              'Se generará una clave privada que nunca sale del almacén seguro del equipo. '
              'Solo puede haber un dispositivo activo por carnet.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _ocupado ? null : _vincular,
              icon: const Icon(Icons.phonelink_lock_outlined),
              label: Text(_ocupado ? 'Vinculando…' : 'Vincular dispositivo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaQr(BuildContext context) {
    final certificado = _resumen!.certificado!;
    final colores = Theme.of(context).colorScheme;

    if (certificado.vencido) {
      return Card(
        color: colores.errorContainer.withValues(alpha: 0.4),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('El certificado venció. Conéctate para renovar el carnet.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              tabs: const [Tab(text: 'QR dinámico'), Tab(text: 'Código de barras')],
            ),
            SizedBox(
              height: 360,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _vistaQr(context),
                  _vistaBarras(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaQr(BuildContext context) {
    final qr = _qr;
    if (qr == null) {
      return const Center(child: Text('Preparando el QR…'));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.white,
          child: QrImageView(
            data: qr,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
            size: 250,
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Se renueva en $_segundos s',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          'Úsalo solo en el torniquete: una captura de pantalla deja de ser válida.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _vistaBarras(BuildContext context) {
    final codigo = _resumen!.carnet.codigoBarras;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        BarcodeWidget(
          barcode: Barcode.code128(),
          data: codigo,
          width: 300,
          height: 110,
          drawText: true,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: const [
            Chip(label: Text('Biblioteca')),
            Chip(label: Text('Bicicletero')),
            Chip(label: Text('Parqueadero')),
            Chip(label: Text('Préstamo de equipos')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Identificador no firmado: no se usa para validar el ingreso.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _fecha(DateTime fecha) => '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}

class _Banner extends StatelessWidget {
  const _Banner({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(texto),
    );
  }
}
