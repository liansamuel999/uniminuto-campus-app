import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/api/api_client.dart';

/// Errores de autenticación traducidos a mensajes para la interfaz.
class ErrorAutenticacion implements Exception {
  ErrorAutenticacion(this.mensaje, {this.codigo});

  final String mensaje;
  final String? codigo;

  @override
  String toString() => mensaje;
}

/// Acceso a Firebase Authentication (§3.2): login, logout y cambio de contraseña con
/// reautenticación previa (D-34).
class AuthRepository {
  AuthRepository(this._auth, this._api);

  final FirebaseAuth _auth;
  final ApiClient _api;

  ApiClient get api => _api;

  Stream<User?> get cambiosDeSesion => _auth.authStateChanges();

  User? get usuarioActual => _auth.currentUser;

  Future<String?> idToken({bool refrescar = false}) async {
    return _auth.currentUser?.getIdToken(refrescar);
  }

  Future<UserCredential> iniciarSesion(String correo, String contrasena) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: correo.trim(),
        password: contrasena,
      );
    } on FirebaseAuthException catch (error) {
      throw ErrorAutenticacion(_mensajeDeError(error.code), codigo: error.code);
    }
  }

  Future<void> cerrarSesion() => _auth.signOut();

  /// Exige la contraseña actual antes de cambiarla (flujo real de Firebase, D-34).
  Future<void> cambiarContrasena({
    required String contrasenaActual,
    required String contrasenaNueva,
  }) async {
    final usuario = _auth.currentUser;
    if (usuario?.email == null) {
      throw ErrorAutenticacion('No hay una sesión con correo para cambiar la contraseña');
    }
    final credencial = EmailAuthProvider.credential(
      email: usuario!.email!,
      password: contrasenaActual,
    );
    try {
      await usuario.reauthenticateWithCredential(credencial);
      await usuario.updatePassword(contrasenaNueva);
    } on FirebaseAuthException catch (error) {
      throw ErrorAutenticacion(_mensajeDeError(error.code), codigo: error.code);
    }
  }

  /// Mensajes deliberadamente genéricos: no revelan si el correo existe, si la contraseña
  /// tiene cierta longitud ni cuál de los dos datos falló (§8, tratamiento de datos).
  String _mensajeDeError(String codigo) {
    switch (codigo) {
      case 'user-disabled':
        return 'No fue posible iniciar sesión. Contacta a la oficina de registro.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'No hay conexión con el servicio de acceso. Revisa tu red.';
      case 'requires-recent-login':
        return 'Por seguridad, vuelve a iniciar sesión antes de cambiar la contraseña.';
      case 'weak-password':
        return 'La nueva contraseña no cumple los requisitos de seguridad.';
      default:
        return 'Correo o contraseña incorrectos.';
    }
  }
}
