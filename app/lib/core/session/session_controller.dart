import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/perfil/domain/perfil_usuario.dart';
import '../providers/app_providers.dart';

/// Sesión activa: identidad de Firebase, perfil de la API y roles de los *custom claims*.
class Sesion {
  const Sesion({
    required this.uid,
    required this.perfil,
    required this.roles,
    this.correo,
  });

  final String uid;
  final PerfilUsuario perfil;
  final List<String> roles;
  final String? correo;

  /// Rol con el que se pinta la navegación; el servidor autoriza por los claims completos (D-21).
  String? get rolPorDefecto => roles.isEmpty ? null : roles.first;
}

/// Usuario de Firebase (o `null` si no hay sesión). Es la fuente de verdad de la autenticación.
final usuarioFirebaseProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Sesión completa: espera al usuario, lee los claims y pide `GET /mi-perfil`.
final sesionProvider = FutureProvider<Sesion?>((ref) async {
  final usuario = await ref.watch(usuarioFirebaseProvider.future);
  if (usuario == null) return null;

  final repositorio = ref.watch(authRepositoryProvider);
  final resultadoDelToken = await usuario.getIdTokenResult(true);
  final rolesDelClaim = (resultadoDelToken.claims?['roles'] as List<dynamic>? ?? const [])
      .map((rol) => '$rol')
      .toList(growable: false);

  final json = await repositorio.api.getJson('/mi-perfil');
  final perfil = PerfilUsuario.fromJson(json);

  return Sesion(
    uid: usuario.uid,
    correo: usuario.email,
    perfil: perfil,
    roles: rolesDelClaim.isNotEmpty ? rolesDelClaim : perfil.roles,
  );
});

/// Rol elegido en la interfaz (solo afecta la navegación; no cambia permisos).
final rolActivoProvider = StateProvider<String?>((ref) => null);

/// Rol efectivo para pintar la barra inferior.
String? rolEfectivo(WidgetRef ref, Sesion sesion) {
  final elegido = ref.watch(rolActivoProvider);
  if (elegido != null && sesion.roles.contains(elegido)) return elegido;
  return sesion.rolPorDefecto;
}
