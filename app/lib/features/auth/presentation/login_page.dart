import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/firebase_bootstrap.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/widgets/aviso_muestra.dart';

/// Pantalla de acceso (§9, Fase 1 completa la autenticación real con Firebase).
///
/// En la Fase 0B todavía no hay proyecto FlutterFire configurado, así que el formulario se muestra
/// deshabilitado y se ofrece el modo muestra para verificar el esqueleto de navegación.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  bool _ocultarContrasena = true;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseListo = ref.watch(firebaseDisponibleProvider);
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.school_rounded, size: 56, color: colores.primary),
                  const SizedBox(height: 12),
                  Text(
                    AppConfig.nombreApp,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Carnet, notas y aulas en una sola app',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colores.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  const AvisoMuestra(),
                  const SizedBox(height: 24),
                  if (!firebaseListo) ...[
                    Card(
                      color: colores.secondaryContainer.withValues(alpha: 0.45),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top, color: colores.onSecondaryContainer),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'La autenticación real con Firebase se habilita en la Fase 1. '
                                'Mientras tanto puedes recorrer el esqueleto en modo muestra.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _correo,
                          enabled: firebaseListo,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo institucional',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: (valor) =>
                              (valor == null || !valor.contains('@')) ? 'Escribe un correo válido' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _contrasena,
                          enabled: firebaseListo,
                          obscureText: _ocultarContrasena,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _ocultarContrasena ? 'Mostrar contraseña' : 'Ocultar contraseña',
                              onPressed: () => setState(() => _ocultarContrasena = !_ocultarContrasena),
                              icon: Icon(
                                _ocultarContrasena ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (valor) =>
                              (valor == null || valor.length < 8) ? 'Mínimo 8 caracteres' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: firebaseListo
                        ? () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('El inicio de sesión real llega en la Fase 1.')),
                            )
                        : null,
                    child: const Text('Iniciar sesión'),
                  ),
                  if (!AppConfig.esProduccion) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(sessionProvider.notifier).entrarEnModoMuestra(),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Entrar en modo muestra'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Proyecto de muestra para un trabajo universitario. Sin integración con Génesis, '
                    'U-Wallet ni torniquetes.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colores.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
