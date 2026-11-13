import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/widgets/aviso_muestra.dart';

class _Acceso {
  const _Acceso(this.titulo, this.descripcion, this.icono, this.ruta, this.fase);

  final String titulo;
  final String descripcion;
  final IconData icono;
  final String? ruta;
  final String fase;
}

/// Pantalla de inicio con los accesos a los módulos del rol activo.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const List<_Acceso> _accesos = <_Acceso>[
    _Acceso('Carnet digital', 'QR dinámico, código de barras y dispositivo vinculado.', Icons.badge_outlined, '/carnet', 'Fase 2'),
    _Acceso('Aulas virtuales', 'Contenidos, tareas y foros de tus asignaturas.', Icons.school_outlined, '/aulas', 'Fase 3'),
    _Acceso('Horario y notas', 'Asignaturas, cortes y ubicación de tu salón.', Icons.event_note_outlined, null, 'Fase 4'),
    _Acceso('Reservas', 'Cabinas y salas de autorecreación por hora.', Icons.event_seat_outlined, '/reservas', 'Nueva'),
    _Acceso('Perfil', 'Datos de la cuenta, roles y cambio de contraseña.', Icons.person_outline, '/perfil', 'Fase 1'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final colores = Theme.of(context).colorScheme;
    final rol = sesion == null ? null : rolEfectivo(ref, sesion);

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
            '${sesion?.perfil.programa?.nombre ?? 'Sin programa'} · ${sesion?.perfil.codigoInstitucional ?? 'Sin código'}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const AvisoMuestra(compacto: true),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
            children: [
              for (final acceso in _accesos)
                _TarjetaAcceso(
                  acceso: acceso,
                  habilitado: acceso.ruta != null,
                  onTap: acceso.ruta == null ? null : () => context.go(acceso.ruta!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaAcceso extends StatelessWidget {
  const _TarjetaAcceso({required this.acceso, required this.habilitado, this.onTap});

  final _Acceso acceso;
  final bool habilitado;
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(acceso.icono, size: 28, color: habilitado ? colores.primary : colores.outline),
              const Spacer(),
              Text(acceso.titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                acceso.descripcion,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(acceso.fase, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colores.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
