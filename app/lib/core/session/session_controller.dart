import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Roles de la matriz RBAC (§5), en el mismo orden que la API.
const List<String> rolesDelSistema = <String>[
  'ESTUDIANTE',
  'DOCENTE',
  'ADMIN_ACADEMICO',
  'ADMIN_ESPACIOS',
  'SEGURIDAD',
  'SOPORTE',
  'AUDITOR',
];

/// Estado de sesión del cliente. El rol activo es solo de interfaz (D-21).
class SessionState {
  const SessionState({this.uid, this.roles = const <String>[], this.rolActivo});

  final String? uid;
  final List<String> roles;
  final String? rolActivo;

  bool get autenticado => uid != null;

  SessionState copyWith({
    String? uid,
    List<String>? roles,
    String? rolActivo,
  }) {
    return SessionState(
      uid: uid ?? this.uid,
      roles: roles ?? this.roles,
      rolActivo: rolActivo ?? this.rolActivo,
    );
  }
}

/// Sesión de la app. En la Fase 0B solo admite el modo muestra; la Fase 1 la conecta a Firebase.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  /// Entrada temporal para verificar el esqueleto sin Firebase (se retira en la Fase 1).
  void entrarEnModoMuestra() {
    state = const SessionState(
      uid: 'modo-muestra',
      roles: <String>['ESTUDIANTE'],
      rolActivo: 'ESTUDIANTE',
    );
  }

  void cambiarRolActivo(String rol) {
    if (!state.roles.contains(rol)) return;
    state = state.copyWith(rolActivo: rol);
  }

  void cerrarSesion() {
    state = const SessionState();
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
