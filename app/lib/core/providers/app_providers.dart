import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/academico/data/repositorio_academico.dart';
import '../../../features/admin/data/repositorio_admin.dart';
import '../../../features/aulas/data/comunicacion_repository.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';

/// Instancia única de Firebase Authentication.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Foros y anuncios (la API valida acceso y usa Firestore con el Admin SDK, D-78).
final comunicacionRepositoryProvider = Provider<RepositorioComunicacion>(
  (ref) => RepositorioComunicacion(ref.watch(apiClientProvider)),
);

/// Lecturas académicas con caché offline (Fase 4, D-40).
final repositorioAcademicoProvider = Provider<RepositorioAcademico>(
  (ref) => RepositorioAcademico(ref.watch(apiClientProvider)),
);

/// Paneles administrativos y auditoría (Fase 5).
final repositorioAdminProvider = Provider<RepositorioAdmin>(
  (ref) => RepositorioAdmin(ref.watch(apiClientProvider)),
);

/// Cliente de la API con el ID Token adjunto en cada petición (§3.2).
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: () async => auth.currentUser?.getIdToken(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(apiClientProvider));
});
