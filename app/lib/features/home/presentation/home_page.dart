import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/widgets/aviso_muestra.dart';

class _Acceso {
  const _Acceso(this.titulo, this.icono, this.ruta);

  final String titulo;
  final IconData icono;
  final String ruta;
}

/// Inicio con accesos rápidos **distintos por rol**; en móvil solo se muestra el título.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static List<_Acceso> _accesosPara(String? rol) {
    const aulas = _Acceso('Aulas virtuales', Icons.school_outlined, '/aulas');
    const horario = _Acceso('Horario', Icons.calendar_month_outlined, '/horario');
    const notas = _Acceso('Mis notas', Icons.grading_outlined, '/notas');
    const asignaturas = _Acceso('Mis asignaturas', Icons.menu_book_outlined, '/asignaturas');
    const bandeja = _Acceso('Bandeja', Icons.mark_email_unread_outlined, '/correos');
    const reservas = _Acceso('Reservas', Icons.event_seat_outlined, '/reservas');
    const incidencias = _Acceso('Incidencias', Icons.report_outlined, '/incidencias');
    const perfil = _Acceso('Mi perfil', Icons.person_outline, '/perfil');
    const adminAcademico = _Acceso(
      'Administración académica',
      Icons.admin_panel_settings_outlined,
      '/admin-academico',
    );
    const miQr = _Acceso('Mi QR de ingreso', Icons.qr_code_2_outlined, '/carnet');
    const gestionIncidencias = _Acceso('Gestión de incidencias', Icons.support_agent_outlined, '/incidencias');
    const auditoria = _Acceso('Auditoría', Icons.shield_outlined, '/auditoria');

    switch (rol) {
      case 'DOCENTE':
        return [aulas, horario, asignaturas, notas, bandeja, incidencias, perfil];
      case 'ADMIN_ACADEMICO':
        return [adminAcademico, miQr, incidencias, perfil];
      case 'ADMIN_ESPACIOS':
        // Rol absorbido por la administración académica (D-85): se conserva por compatibilidad.
        return [adminAcademico, miQr, incidencias, perfil];
      case 'SOPORTE':
        return [gestionIncidencias, perfil];
      case 'AUDITOR':
        return [auditoria, perfil];
      case 'SEGURIDAD':
        return [miQr, incidencias, perfil];
      default:
        // Estudiante: primero lo que más usa (aulas y horario), bandeja después.
        return [aulas, horario, notas, asignaturas, bandeja, reservas, incidencias, perfil];
    }
  }

  String _subtitulo(Sesion? sesion, String? rol) {
    if (sesion == null) return '';
    if (sesion.roles.contains('ESTUDIANTE')) {
      final programa = sesion.perfil.programa?.nombre ?? 'Sin programa';
      final codigo = sesion.perfil.codigoInstitucional ?? 'Sin código';
      return '$programa · $codigo';
    }
    return switch (rol) {
      'DOCENTE' => 'Portal docente',
      'ADMIN_ACADEMICO' => 'Administración académica',
      'ADMIN_ESPACIOS' => 'Administración académica',
      'SOPORTE' => 'Soporte',
      'AUDITOR' => 'Auditoría',
      'SEGURIDAD' => 'Personal de seguridad',
      _ => 'Personal universitario',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final colores = Theme.of(context).colorScheme;
    final rol = sesion == null ? null : rolEfectivo(ref, sesion);
    final accesos = _accesosPara(rol);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(Icons.verified_user_outlined, size: 18, color: colores.primary),
              label: Text(rol ?? 'Sin rol'),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Hola, ${sesion?.perfil.nombres ?? 'invitado'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitulo(sesion, rol),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const AvisoMuestra(compacto: true),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              for (final acceso in accesos)
                _TarjetaAcceso(acceso: acceso, onTap: () => context.go(acceso.ruta)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaAcceso extends StatelessWidget {
  const _TarjetaAcceso({required this.acceso, this.onTap});

  final _Acceso acceso;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Card(
      color: colores.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(acceso.icono, size: 26, color: colores.primary),
              const SizedBox(height: 8),
              Text(
                acceso.titulo,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
