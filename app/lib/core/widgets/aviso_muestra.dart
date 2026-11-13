import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Aviso visible de que la app es una muestra con datos ficticios (§8, D-43).
class AvisoMuestra extends StatelessWidget {
  const AvisoMuestra({super.key, this.compacto = false});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compacto ? 6 : 10),
      decoration: BoxDecoration(
        color: colores.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: compacto ? 16 : 18, color: colores.onTertiaryContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              AppConfig.avisoMuestra,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colores.onTertiaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
