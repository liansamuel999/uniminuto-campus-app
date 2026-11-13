import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Configuración de idioma de la app (español de Colombia, §9).
///
/// Los delegados son obligatorios: sin `GlobalMaterialLocalizations`, cualquier widget de
/// Material (TextField, DatePicker, tooltips) lanza "No MaterialLocalizations found".
const Locale localeEspanol = Locale('es', 'CO');

const List<Locale> localesSoportados = <Locale>[
  localeEspanol,
  Locale('es'),
  Locale('en'),
];

const List<LocalizationsDelegate<dynamic>> delegadosDeLocalizacion =
    <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
