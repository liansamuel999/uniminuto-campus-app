import 'dart:convert';

import 'package:flutter/services.dart';

/// Carga el JWKS público institucional embebido en el build del validador (§6.1, D-25).
/// La clave privada institucional nunca está en la app.
Future<Map<String, Map<String, dynamic>>> cargarClavesInstitucionales({AssetBundle? bundle}) async {
  final texto = await (bundle ?? rootBundle).loadString('assets/keys/institution_jwks.json');
  final documento = jsonDecode(texto) as Map<String, dynamic>;
  final claves = (documento['keys'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  return {for (final clave in claves) '${clave['kid']}': clave};
}
