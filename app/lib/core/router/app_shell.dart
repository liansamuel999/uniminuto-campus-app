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

/// Barra de navegación inferior **por rol** (§5, D-38): cada perfil ve solo sus módulos.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  List<_Destino> _destinosPara(String? rol) {
    const inicio = _Destino('/inicio', 'Inicio', Icons.home_outlined, Icons.home);
    const carnet = _Destino('/carnet', 'Carnet', Icons.badge_outlined, Icons.badge);
    const miQr = _Destino('/carnet', 'Mi QR', Icons.qr_code_2_outlined, Icons.qr_code_2);
    const aulas = _Destino('/aulas', 'Aulas', Icons.school_outlined, Icons.school);
    const horario = _Destino('/horario', 'Horario', Icons.calendar_month_outlined, Icons.calendar_month);
    const perfil = _Destino('/perfil', 'Perfil', Icons.person_outline, Icons.person);
    const incidencias = _Destino('/incidencias', 'Incidencias', Icons.report_outlined, Icons.report);
    const adminAcademico = _Destino(
      '/admin-academico',
      'Administración',
      Icons.admin_panel_settings_outlined,
      Icons.admin_panel_settings,
    );
    const adminEspacios = _Destino('/admin-espacios', 'Espacios', Icons.domain_outlined, Icons.domain);
    const auditoria = _Destino('/auditoria', 'Auditoría', Icons.shield_outlined, Icons.shield);

    switch (rol) {
      case 'DOCENTE':
        return [inicio, aulas, horario, miQr, perfil];
      case 'ADMIN_ACADEMICO':
        return [inicio, adminAcademico, perfil];
      case 'ADMIN_ESPACIOS':
        return [inicio, adminEspacios, perfil];
      case 'SOPORTE':
        return [inicio, incidencias, perfil];
      case 'AUDITOR':
        return [inicio, auditoria, perfil];
      case 'SEGURIDAD':
        // El personal de seguridad solo reporta incidencias; no usa el validador de QR.
        return [inicio, incidencias, perfil];
      default:
        return [inicio, carnet, aulas, horario, perfil];
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
