import 'package:flutter/material.dart';

import '../../../core/widgets/proximamente_page.dart';

/// Pestaña del carnet. El QR dinámico, el código de barras y la vinculación llegan en la Fase 2.
class CarnetPage extends StatelessWidget {
  const CarnetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProximamentePage(
      titulo: 'Carnet digital',
      descripcion:
          'Aquí verás tu carnet con QR firmado y código de barras, disponibles incluso sin conexión.',
      fase: 'Fase 2',
      icono: Icons.badge_outlined,
    );
  }
}
