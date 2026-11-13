import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../auth/data/auth_repository.dart';

/// Cambio de contraseña con reautenticación previa (D-34) y mínimo de 8 caracteres.
class CambiarContrasenaDialog extends ConsumerStatefulWidget {
  const CambiarContrasenaDialog({super.key});

  @override
  ConsumerState<CambiarContrasenaDialog> createState() => _CambiarContrasenaDialogState();
}

class _CambiarContrasenaDialogState extends ConsumerState<CambiarContrasenaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).cambiarContrasena(
            contrasenaActual: _actual.text,
            contrasenaNueva: _nueva.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada correctamente.')),
      );
    } on ErrorAutenticacion catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _actual,
              enabled: !_guardando,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (valor) => (valor == null || valor.isEmpty) ? 'Escribe tu contraseña actual' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nueva,
              enabled: !_guardando,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
              validator: (valor) =>
                  (valor == null || valor.length < 8) ? 'Mínimo 8 caracteres' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmacion,
              enabled: !_guardando,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repetir nueva contraseña'),
              validator: (valor) => valor != _nueva.text ? 'Las contraseñas no coinciden' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _cambiar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Cambiar'),
        ),
      ],
    );
  }
}
