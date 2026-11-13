import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/carnet/presentation/carnet_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/perfil/presentation/perfil_page.dart';
import '../session/session_controller.dart';
import '../widgets/proximamente_page.dart';
import 'app_shell.dart';

/// Rutas declarativas con guarda por sesión (§3.2, D-38). Las guardas por rol llegan en la Fase 1.
final routerProvider = Provider<GoRouter>((ref) {
  final autenticado = ref.watch(sessionProvider.select((sesion) => sesion.autenticado));

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: false,
    redirect: (context, estado) {
      final enLogin = estado.matchedLocation == '/login';
      if (!autenticado && !enLogin) return '/login';
      if (autenticado && enLogin) return '/inicio';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, estado) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, estado, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/inicio',
            name: 'inicio',
            builder: (context, estado) => const HomePage(),
          ),
          GoRoute(
            path: '/carnet',
            name: 'carnet',
            builder: (context, estado) => const CarnetPage(),
          ),
          GoRoute(
            path: '/aulas',
            name: 'aulas',
            builder: (context, estado) => const ProximamentePage(
              titulo: 'Aulas virtuales',
              descripcion: 'Contenidos, tareas, cuestionarios y foros de tus asignaturas.',
              fase: 'Fase 3',
              icono: Icons.school_outlined,
            ),
          ),
          GoRoute(
            path: '/validador',
            name: 'validador',
            builder: (context, estado) => const ProximamentePage(
              titulo: 'Modo validador',
              descripcion: 'Validación offline del QR del carnet para el personal de seguridad.',
              fase: 'Fase 2',
              icono: Icons.qr_code_scanner_outlined,
            ),
          ),
          GoRoute(
            path: '/perfil',
            name: 'perfil',
            builder: (context, estado) => const PerfilPage(),
          ),
        ],
      ),
    ],
  );
});
