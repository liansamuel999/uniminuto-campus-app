import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/firebase_bootstrap.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/aviso_muestra.dart';
import '../data/auth_repository.dart';

/// Pantalla de acceso con Firebase Authentication (correo + contraseña, §3.2).
///
/// Los mensajes de error son siempre genéricos: no se valida la longitud de la contraseña antes
/// de enviar ni se distingue entre correo inexistente y contraseña incorrecta.
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
      if (mounted) setState(() => _error = 'Correo o contraseña incorrectos.');
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
                          'No se pudo inicializar el servicio de acceso. Revisa la configuración y la conexión.',
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
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo institucional',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: (valor) =>
                              (valor ?? '').trim().isEmpty ? 'Escribe tu correo institucional' : null,
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
                              (valor == null || valor.isEmpty) ? 'Escribe tu contraseña' : null,
                          onFieldSubmitted: (_) => _ingresar(),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colores.errorContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!, style: TextStyle(color: colores.onErrorContainer)),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
