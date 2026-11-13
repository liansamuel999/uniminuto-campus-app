import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/phone_frame.dart';

/// Raíz de la app: tema, navegación y marco de teléfono para Web (§7.5).
class CampusApp extends ConsumerWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.nombreApp,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro(),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO')],
      routerConfig: router,
      builder: (context, child) => PhoneFrame(child: child ?? const SizedBox.shrink()),
    );
  }
}
