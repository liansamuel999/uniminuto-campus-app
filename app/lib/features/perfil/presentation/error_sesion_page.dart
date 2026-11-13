import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';

/// Pantalla cuando la sesión existe en Firebase pero el perfil no se pudo cargar
/// (API caída, migraciones pendientes o usuario sin registro en la base).
class ErrorSesionPage extends ConsumerWidget {
  const ErrorSesionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final error = sesion.error;
    final mensaje = error is ApiException
        ? '${error.mensaje}${error.codigo == 'NO_ENCONTRADO' ? '\n\nTu cuenta existe en Firebase pero no está registrada en la base de datos. Ejecuta `npm run db:seed`.' : ''}'
        : 'No se pudo cargar tu perfil. Revisa que la API esté disponible.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 56, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'No pudimos completar tu sesión',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(mensaje, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(sesionProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
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
        ),
      ),
    );
  }
}
