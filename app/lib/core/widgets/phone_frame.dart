import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// En pantallas anchas y en Web, la app se dibuja dentro de un marco de teléfono (§7.5, D-39).
///
/// Se aplica una sola vez, en la raíz; las pantallas no saben nada de esto.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child, this.forzarWeb});

  final Widget child;

  /// Permite forzar el comportamiento de Web en pruebas (por defecto usa `kIsWeb`).
  final bool? forzarWeb;

  bool get _esWeb => forzarWeb ?? AppConfig.esWeb;

  @override
  Widget build(BuildContext context) {
    if (!_esWeb) return child;

    return LayoutBuilder(
      builder: (context, restricciones) {
        if (restricciones.maxWidth <= AppConfig.anchoRuptura) return child;

        final alto = restricciones.maxHeight.isFinite ? restricciones.maxHeight : null;
        return ColoredBox(
          color: const Color(0xFFE9EBEF),
          child: Center(
            child: Container(
              width: AppConfig.anchoMovil,
              height: alto,
              margin: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFD3D7DE)),
                boxShadow: const [
                  BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
