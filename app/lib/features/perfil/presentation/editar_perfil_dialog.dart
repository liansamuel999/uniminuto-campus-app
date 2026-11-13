import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../domain/perfil_usuario.dart';

/// Edición de los datos que el usuario puede cambiar de su propio perfil (§7.7).
class EditarPerfilDialog extends ConsumerStatefulWidget {
  const EditarPerfilDialog({super.key, required this.perfil});

  final PerfilUsuario perfil;

  @override
  ConsumerState<EditarPerfilDialog> createState() => _EditarPerfilDialogState();
}

class _EditarPerfilDialogState extends ConsumerState<EditarPerfilDialog> {
  late final TextEditingController _nombres = TextEditingController(text: widget.perfil.nombres);
  late final TextEditingController _apellidos = TextEditingController(text: widget.perfil.apellidos);
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombres.dispose();
    _apellidos.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).putJson('/mi-perfil', cuerpo: {
        'nombres': _nombres.text.trim(),
        'apellidos': _apellidos.text.trim(),
      });
      ref.invalidate(sesionProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar perfil'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nombres,
            enabled: !_guardando,
            decoration: const InputDecoration(labelText: 'Nombres'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apellidos,
            enabled: !_guardando,
            decoration: const InputDecoration(labelText: 'Apellidos'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
