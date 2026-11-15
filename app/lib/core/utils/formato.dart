import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Utilidades de formato de fecha/hora y de tiempo restante para las pantallas.
String fechaCorta(DateTime? fecha) {
  if (fecha == null) return '—';
  final local = fecha.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String fechaHoraCorta(DateTime? fecha) {
  if (fecha == null) return '—';
  final local = fecha.toLocal();
  return '${fechaCorta(local)} ${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// «2 d 3 h», «5 h 20 min» o «12 min» según lo que falte para [fecha].
String tiempoRestante(DateTime? fecha) {
  if (fecha == null) return 'sin fecha límite';
  final diferencia = fecha.toLocal().difference(DateTime.now());
  if (diferencia.isNegative) return 'plazo vencido';
  final dias = diferencia.inDays;
  final horas = diferencia.inHours % 24;
  final minutos = diferencia.inMinutes % 60;
  if (dias > 0) return '$dias d $horas h';
  if (horas > 0) return '$horas h $minutos min';
  return '$minutos min';
}

/// Abre una URL externa con el navegador/aplicación del dispositivo.
Future<void> abrirEnlace(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('El enlace no es válido.')),
    );
    return;
  }
  try {
    final abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abierto && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace en este dispositivo.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }
}
