import 'package:flutter/material.dart';

/// Pantalla "en construcción" para los módulos que llegan en fases posteriores.
/// Existe en la Fase 0B para que la navegación por rol sea verificable de extremo a extremo.
class ProximamentePage extends StatelessWidget {
  const ProximamentePage({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.fase,
    this.icono = Icons.construction_outlined,
  });

  final String titulo;
  final String descripcion;
  final String fase;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 56, color: colores.primary),
              const SizedBox(height: 16),
              Text(descripcion, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Chip(label: Text('Disponible en la $fase')),
            ],
          ),
        ),
      ),
    );
  }
}
