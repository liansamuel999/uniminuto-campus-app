import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/widgets/aviso_muestra.dart';
import '../domain/perfil_usuario.dart';
import 'cambiar_contrasena_dialog.dart';
import 'editar_perfil_dialog.dart';

/// Perfil propio (§7.7): datos, roles y acciones de cuenta.
class PerfilPage extends ConsumerWidget {
  const PerfilPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final colores = Theme.of(context).colorScheme;

    if (sesion == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final perfil = sesion.perfil;
    final rol = rolEfectivo(ref, sesion);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(sesionProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: colores.primaryContainer,
                          child: Text(
                            _iniciales(perfil),
                            style: TextStyle(
                              color: colores.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                perfil.nombreCompleto,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(perfil.correo, style: Theme.of(context).textTheme.bodySmall),
                              if (perfil.codigoInstitucional != null)
                                Text(
                                  'Código ${perfil.codigoInstitucional}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colores.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Editar perfil',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => EditarPerfilDialog(perfil: perfil),
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (perfil.programa != null) ...[
                      _Dato(etiqueta: 'Programa', valor: perfil.programa!.nombre),
                      const SizedBox(height: 8),
                    ],
                    _Dato(etiqueta: 'Documento', valor: perfil.documento ?? 'No registrado'),
                    const SizedBox(height: 8),
                    _Dato(etiqueta: 'Estado', valor: perfil.estado),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Roles', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Los roles vienen de los permisos de Firebase. El elegido solo cambia lo que ves.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final nombreRol in sesion.roles)
                          ChoiceChip(
                            label: Text(nombreRol),
                            selected: nombreRol == rol,
                            onSelected: (_) => ref.read(rolActivoProvider.notifier).state = nombreRol,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: colores.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: const Icon(Icons.password_outlined),
              title: const Text('Cambiar contraseña'),
              subtitle: const Text('Se pide la contraseña actual (reautenticación).'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const CambiarContrasenaDialog(),
              ),
            ),
            const SizedBox(height: 12),
            const AvisoMuestra(),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Tratamiento de datos'),
                subtitle: const Text(
                  'Muestra académica con datos ficticios. Para datos reales aplicaría la Ley 1581 de '
                  '2012 (Colombia): minimización, finalidad y acceso por rol.',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authRepositoryProvider).cerrarSesion();
                ref.invalidate(sesionProvider);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }

  String _iniciales(PerfilUsuario perfil) {
    final nombres = perfil.nombres.trim();
    final apellidos = perfil.apellidos.trim();
    final inicialNombre = nombres.isEmpty ? '' : nombres[0];
    final inicialApellido = apellidos.isEmpty ? '' : apellidos[0];
    return '$inicialNombre$inicialApellido'.toUpperCase();
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            etiqueta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(child: Text(valor, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
