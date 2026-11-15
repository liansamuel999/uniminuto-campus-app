import 'package:flutter/material.dart';

/// Tema Material 3 de la muestra (§9): claro, institucional y sin logotipos oficiales.
abstract final class AppTheme {
  /// Azul institucional neutro (D-37).
  static const Color colorInstitucional = Color(0xFF1B3A6B);
  static const Color colorAcento = Color(0xFF2F6FED);

  static ThemeData claro() {
    final esquema = ColorScheme.fromSeed(
      seedColor: colorInstitucional,
      brightness: Brightness.light,
    ).copyWith(secondary: colorAcento);

    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: esquema.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: esquema.surface,
        foregroundColor: esquema.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: esquema.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(96, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(96, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: esquema.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(88, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
      // Campos con borde visible (antes se confundían con el fondo de los diálogos).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: esquema.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: borde,
        enabledBorder: borde,
        disabledBorder: borde,
        focusedBorder: borde.copyWith(
          borderSide: BorderSide(color: esquema.primary, width: 1.6),
        ),
        errorBorder: borde.copyWith(borderSide: BorderSide(color: esquema.error)),
        focusedErrorBorder: borde.copyWith(
          borderSide: BorderSide(color: esquema.error, width: 1.6),
        ),
      ),
      // Diálogos de tamaño móvil: se mantienen modales con el fondo oscurecido y acciones
      // con botones de tamaño táctil (Cancelar / Guardar).
      dialogTheme: DialogThemeData(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Color(0xFFFFFFFF),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: esquema.surface,
        indicatorColor: esquema.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
