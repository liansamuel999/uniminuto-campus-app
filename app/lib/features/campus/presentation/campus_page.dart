import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';

/// Jerarquía del campus: Edificio → Piso → Salón (§4.3, §7.7).
class CampusPage extends ConsumerStatefulWidget {
  const CampusPage({super.key});

  @override
  ConsumerState<CampusPage> createState() => _CampusPageState();
}

class _CampusPageState extends ConsumerState<CampusPage> {
  List<dynamic> _edificios = const [];
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
      final edificios = await ref.read(repositorioAcademicoProvider).edificios();
      if (mounted) setState(() => _edificios = edificios);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el campus.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Calle 80'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_cargando && _error == null && _edificios.isEmpty)
              const Text('El campus no tiene edificios registrados.'),
            for (final edificio in _edificios)
              if (edificio is Map) _EdificioTile(edificio: edificio),
          ],
        ),
      ),
    );
  }
}

class _EdificioTile extends ConsumerStatefulWidget {
  const _EdificioTile({required this.edificio});

  final Map<dynamic, dynamic> edificio;

  @override
  ConsumerState<_EdificioTile> createState() => _EdificioTileState();
}

class _EdificioTileState extends ConsumerState<_EdificioTile> {
  Future<List<dynamic>>? _pisos;

  void _alExpandir(bool abierto) {
    if (abierto && _pisos == null) {
      setState(() {
        _pisos = ref.read(repositorioAcademicoProvider).pisos('${widget.edificio['id']}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: const Icon(Icons.apartment_outlined),
        title: Text('${widget.edificio['codigo']} · ${widget.edificio['nombre']}'),
        subtitle: Text(
          'Sede ${widget.edificio['sede']} · ${widget.edificio['pisos']} piso(s)',
        ),
        onExpansionChanged: _alExpandir,
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          if (_pisos == null)
            const Padding(padding: EdgeInsets.all(8), child: Text('Despliega para cargar los pisos.'))
          else
            FutureBuilder<List<dynamic>>(
              future: _pisos,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No se pudieron cargar los pisos.'),
                  );
                }
                final pisos = snapshot.data ?? const [];
                return Column(
                  children: [
                    for (final piso in pisos)
                      if (piso is Map) _PisoTile(piso: piso),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PisoTile extends ConsumerStatefulWidget {
  const _PisoTile({required this.piso});

  final Map<dynamic, dynamic> piso;

  @override
  ConsumerState<_PisoTile> createState() => _PisoTileState();
}

class _PisoTileState extends ConsumerState<_PisoTile> {
  Future<List<dynamic>>? _salones;

  void _alExpandir(bool abierto) {
    if (abierto && _salones == null) {
      setState(() {
        _salones = ref.read(repositorioAcademicoProvider).salones('${widget.piso['id']}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: CircleAvatar(child: Text('${widget.piso['numero']}')),
      title: Text('Piso ${widget.piso['numero']} · ${widget.piso['tipo']}'),
      subtitle: Text('${widget.piso['salones']} salón(es)'),
      onExpansionChanged: _alExpandir,
      childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      children: [
        if (_salones == null)
          const Padding(padding: EdgeInsets.all(8), child: Text('Despliega para ver los salones.'))
        else
          FutureBuilder<List<dynamic>>(
            future: _salones,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No se pudieron cargar los salones.'),
                );
              }
              final salones = snapshot.data ?? const [];
              if (salones.isEmpty) {
                return const Padding(padding: EdgeInsets.all(8), child: Text('Sin salones.'));
              }
              return Column(
                children: [
                  for (final salon in salones)
                    if (salon is Map)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.meeting_room_outlined, size: 20),
                        title: Text('${salon['codigo']}'),
                        subtitle: Text('${salon['tipo']} · capacidad ${salon['capacidad']}'),
                      ),
                ],
              );
            },
          ),
      ],
    );
  }
}
