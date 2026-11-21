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
  final _respuestaCaptcha = TextEditingController();
  bool _ocultarContrasena = true;
  bool _enviando = false;
  bool _verificandoCaptcha = false;
  bool _captchaVerificado = false;
  String? _captchaId;
  String? _captchaToken;
  String? _captchaPregunta;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCaptcha();
  }

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    _respuestaCaptcha.dispose();
    super.dispose();
  }

  Future<void> _cargarCaptcha() async {
    try {
      final datos = await ref.read(apiClientProvider).postJson('/auth/captcha');
      if (!mounted) return;
      setState(() {
        _captchaId = '${datos['id']}';
        _captchaToken = '${datos['token']}';
        _captchaPregunta = '${datos['pregunta']}';
        _captchaVerificado = false;
        _respuestaCaptcha.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la verificación de seguridad.');
    }
  }

  Future<void> _verificarCaptcha() async {
    if (_captchaId == null || _captchaToken == null) return;
    final respuesta = int.tryParse(_respuestaCaptcha.text.trim());
    if (respuesta == null) {
      setState(() => _error = 'Escribe la respuesta de la verificación.');
      return;
    }
    setState(() {
      _verificandoCaptcha = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).postJson('/auth/captcha/verificar', cuerpo: {
        'id': _captchaId,
        'respuesta': respuesta,
        'token': _captchaToken,
      });
      if (mounted) {
        setState(() {
          _captchaVerificado = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Respuesta incorrecta. Solicita una nueva verificación.');
        await _cargarCaptcha();
      }
    } finally {
      if (mounted) setState(() => _verificandoCaptcha = false);
    }
  }

  Future<void> _ingresar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_captchaVerificado) {
      setState(() => _error = 'Resuelve la verificación de seguridad antes de entrar.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).iniciarSesion(_correo.text, _contrasena.text);
      // La navegación la resuelve el router al cambiar el estado de sesión.
    } on ErrorAutenticacion catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
      await _cargarCaptcha();
    } catch (_) {
      if (mounted) setState(() => _error = 'Correo o contraseña incorrectos.');
      await _cargarCaptcha();
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
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Verificación de seguridad',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          if (_captchaVerificado)
                            Row(
                              children: [
                                Icon(Icons.verified_outlined, color: colores.primary),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Verificación completada.')),
                              ],
                            )
                          else ...[
                            Text(_captchaPregunta ?? 'Cargando verificación…'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _respuestaCaptcha,
                                    enabled: !_verificandoCaptcha && _captchaPregunta != null,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Respuesta',
                                      isDense: true,
                                    ),
                                    onSubmitted: (_) => _verificarCaptcha(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _verificandoCaptcha || _captchaPregunta == null
                                      ? null
                                      : _verificarCaptcha,
                                  child: _verificandoCaptcha
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Verificar'),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _verificandoCaptcha ? null : _cargarCaptcha,
                                child: const Text('Otra pregunta'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_enviando || !firebaseListo || !_captchaVerificado) ? null : _ingresar,
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
