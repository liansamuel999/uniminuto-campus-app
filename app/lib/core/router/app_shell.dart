import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../session/session_controller.dart';

class _Destino {
  const _Destino(this.ruta, this.etiqueta, this.icono, this.iconoActivo);

  final String ruta;
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
}

/// Barra de navegación inferior dependiente del rol (§5, D-38).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  List<_Destino> _destinosPara(String? rol) {
    const inicio = _Destino('/inicio', 'Inicio', Icons.home_outlined, Icons.home);
    const carnet = _Destino('/carnet', 'Carnet', Icons.badge_outlined, Icons.badge);
    const aulas = _Destino('/aulas', 'Aulas', Icons.school_outlined, Icons.school);
    const perfil = _Destino('/perfil', 'Perfil', Icons.person_outline, Icons.person);
    const validador = _Destino(
      '/validador',
      'Validador',
      Icons.qr_code_scanner_outlined,
      Icons.qr_code_scanner,
    );

    switch (rol) {
      case 'SEGURIDAD':
        return const [inicio, validador, perfil];
      case 'DOCENTE':
      case 'ADMIN_ACADEMICO':
      case 'ADMIN_ESPACIOS':
      case 'SOPORTE':
      case 'AUDITOR':
        return const [inicio, aulas, perfil];
      default:
        return const [inicio, carnet, aulas, perfil];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final rol = sesion == null ? null : rolEfectivo(ref, sesion);
    final destinos = _destinosPara(rol);
    final ubicacion = GoRouterState.of(context).matchedLocation;

    var indice = destinos.indexWhere((destino) => ubicacion.startsWith(destino.ruta));
    if (indice < 0) indice = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: indice,
        onDestinationSelected: (nuevo) => context.go(destinos[nuevo].ruta),
        destinations: [
          for (final destino in destinos)
            NavigationDestination(
              icon: Icon(destino.icono),
              selectedIcon: Icon(destino.iconoActivo),
              label: destino.etiqueta,
            ),
        ],
      ),
    );
  }
}
