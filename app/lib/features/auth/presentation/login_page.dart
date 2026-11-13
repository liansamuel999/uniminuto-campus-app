import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/firebase_bootstrap.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/aviso_muestra.dart';
import '../data/auth_repository.dart';

/// Pantalla de acceso con Firebase Authentication (correo + contraseña, §3.2).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController(text: AppConfig.esProduccion ? '' : 'juan.rojas@demo.uniminuto.test');
  final _contrasena = TextEditingController(text: AppConfig.esProduccion ? '' : 'Demo1234*');
  bool _ocultarContrasena = true;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).iniciarSesion(_correo.text, _contrasena.text);
      // La navegación la resuelve el router al cambiar el estado de sesión.
    } on ErrorAutenticacion catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo iniciar sesión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
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
                  const SizedBox(height: 16),
                  Icon(Icons.school_rounded, size: 56, color: colores.primary),
                  const SizedBox(height: 12),
                  Text(
                    AppConfig.nombreApp,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Carnet, notas y aulas en una sola app',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  const AvisoMuestra(),
                  const SizedBox(height: 24),
                  if (!firebaseListo)
                    Card(
                      color: colores.errorContainer.withValues(alpha: 0.5),
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Firebase no se pudo inicializar. Revisa `firebase_options.dart` y la conexión.',
                        ),
                      ),
                    ),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _correo,
                          enabled: !_enviando,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo institucional',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: (valor) {
                            final texto = (valor ?? '').trim();
                            if (texto.isEmpty || !texto.contains('@')) return 'Escribe un correo válido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _contrasena,
                          enabled: !_enviando,
                          obscureText: _ocultarContrasena,
                          autofillHints: const [AutofillHints.password],
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
                          onFieldSubmitted: (_) => _ingresar(),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: colores.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_enviando || !firebaseListo) ? null : _ingresar,
                    child: _enviando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Iniciar sesión'),
                  ),
                  if (!AppConfig.esProduccion) ...[
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cuentas de demostración', style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 6),
                            Text(
                              'juan.rojas@demo.uniminuto.test · Docente: carolina.pena@demo.uniminuto.test\n'
                              'Seguridad: jorge.salazar@demo.uniminuto.test · Contraseña: Demo1234*',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
