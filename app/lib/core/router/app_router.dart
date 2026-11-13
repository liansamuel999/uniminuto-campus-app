import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/carnet/presentation/carnet_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/perfil/presentation/perfil_page.dart';
import '../../features/perfil/presentation/error_sesion_page.dart';
import '../../features/validador/presentation/validador_page.dart';
import '../../features/reservaciones/presentation/reservas_page.dart';
import '../../features/aulas/presentation/aulas_page.dart';
import '../../features/academico/presentation/notas_page.dart';
import '../session/session_controller.dart';
import 'app_shell.dart';

/// Rutas declarativas con guarda de sesión (§3.2, D-38).
final routerProvider = Provider<GoRouter>((ref) {
  final sesion = ref.watch(sesionProvider);

  return GoRouter(
    initialLocation: '/cargando',
    debugLogDiagnostics: false,
    redirect: (context, estado) {
      final ruta = estado.matchedLocation;
      final cargando = sesion.isLoading && !sesion.hasValue;

      if (cargando) return ruta == '/cargando' ? null : '/cargando';
      if (sesion.hasError) return ruta == '/error-sesion' ? null : '/error-sesion';

      final autenticado = sesion.valueOrNull != null;
      if (!autenticado) return ruta == '/login' ? null : '/login';
      if (ruta == '/login' || ruta == '/cargando' || ruta == '/error-sesion') return '/inicio';
      return null;
    },
    routes: [
      GoRoute(path: '/cargando', builder: (context, estado) => const _CargandoPage()),
      GoRoute(path: '/login', name: 'login', builder: (context, estado) => const LoginPage()),
      GoRoute(path: '/error-sesion', builder: (context, estado) => const ErrorSesionPage()),
      ShellRoute(
        builder: (context, estado, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/inicio', name: 'inicio', builder: (context, estado) => const HomePage()),
          GoRoute(path: '/carnet', name: 'carnet', builder: (context, estado) => const CarnetPage()),
          GoRoute(path: '/aulas', name: 'aulas', builder: (context, estado) => const AulasPage()),
          GoRoute(path: '/notas', name: 'notas', builder: (context, estado) => const NotasPage()),
          GoRoute(
            path: '/validador',
            name: 'validador',
            builder: (context, estado) => const ValidadorPage(),
          ),
          GoRoute(path: '/perfil', name: 'perfil', builder: (context, estado) => const PerfilPage()),
          GoRoute(path: '/reservas', name: 'reservas', builder: (context, estado) => const ReservasPage()),
        ],
      ),
    ],
  );
});

class _CargandoPage extends StatelessWidget {
  const _CargandoPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando tu sesión…'),
          ],
        ),
      ),
    );
  }
}
