import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/widgets/aviso_muestra.dart';
import '../domain/perfil_usuario.dart';
import 'cambiar_contrasena_dialog.dart';

/// Perfil propio (§7.7): datos, foto, roles y acciones de cuenta.
///
/// Los estudiantes **no** editan sus datos personales: cualquier cambio se gestiona en la
/// oficina de registro. Solo la foto de perfil es editable desde la app.
class PerfilPage extends ConsumerStatefulWidget {
  const PerfilPage({super.key});

  @override
  ConsumerState<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends ConsumerState<PerfilPage> {
  static const XTypeGroup _tiposImagen = XTypeGroup(
    label: 'Imágenes',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
  );

  bool _subiendoFoto = false;

  Future<void> _cambiarFoto(PerfilUsuario perfil) async {
    setState(() => _subiendoFoto = true);
    try {
      final archivo = await openFile(acceptedTypeGroups: const [_tiposImagen]);
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      final mime = archivo.mimeType ?? 'image/jpeg';
      final api = ref.read(apiClientProvider);

      final firma = await api.postJson('/archivos/subida', cuerpo: {
        'contexto': 'PERFIL',
        'nombre': archivo.name,
        'mime': mime,
        'tamano': bytes.length,
      });
      await api.dio.put<dynamic>(
        '${firma['urlPut']}',
        data: bytes,
        options: Options(headers: {'Content-Type': mime}),
      );
      await api.putJson('/mi-perfil', cuerpo: {'fotoKey': firma['objetoKey']});
      ref.invalidate(sesionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada.')),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.mensaje)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo subir la foto. Revisa la conexión.')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final colores = Theme.of(context).colorScheme;

    if (sesion == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final perfil = sesion.perfil;
    final rol = rolEfectivo(ref, sesion);
    final esEstudiante = sesion.roles.contains('ESTUDIANTE');

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(sesionProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Stack(
                          children: [
                            _Avatar(
                              perfil: perfil,
                              iniciales: _iniciales(perfil),
                              subiendo: _subiendoFoto,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Material(
                                color: colores.primary,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: 'Cambiar foto',
                                  onPressed: _subiendoFoto ? null : () => _cambiarFoto(perfil),
                                  iconSize: 16,
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(),
                                  color: colores.onPrimary,
                                  icon: const Icon(Icons.photo_camera_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                perfil.nombreCompleto,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(perfil.correo, style: Theme.of(context).textTheme.bodySmall),
                              if (perfil.codigoInstitucional != null)
                                Text(
                                  'Código ${perfil.codigoInstitucional}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colores.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox.shrink(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (esEstudiante && perfil.programa != null) ...[
                      _Dato(etiqueta: 'Programa', valor: perfil.programa!.nombre),
                      const SizedBox(height: 8),
                    ],
                    _Dato(etiqueta: 'Documento', valor: perfil.documento ?? 'No registrado'),
                    const SizedBox(height: 8),
                    _Dato(etiqueta: 'Estado', valor: perfil.estado),
                    if (esEstudiante) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colores.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: colores.onSurfaceVariant),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Si necesitas cambiar tus datos personales, acércate a la oficina de registro.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rol activo', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Los roles vienen de los permisos de Firebase. El elegido cambia la navegación que ves.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final nombreRol in sesion.roles)
                          ChoiceChip(
                            label: Text(nombreRol),
                            selected: nombreRol == rol,
                            onSelected: (_) => ref.read(rolActivoProvider.notifier).state = nombreRol,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: colores.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: const Icon(Icons.password_outlined),
              title: const Text('Cambiar contraseña'),
              subtitle: const Text('Se pide la contraseña actual (reautenticación).'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const CambiarContrasenaDialog(),
              ),
            ),
            const SizedBox(height: 12),
            const AvisoMuestra(),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Tratamiento de datos'),
                subtitle: const Text(
                  'Muestra académica con datos ficticios. Para datos reales aplicaría la Ley 1581 de '
                  '2012 (Colombia): minimización, finalidad y acceso por rol.',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authRepositoryProvider).cerrarSesion();
                ref.invalidate(sesionProvider);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }

  String _iniciales(PerfilUsuario perfil) {
    final nombres = perfil.nombres.trim();
    final apellidos = perfil.apellidos.trim();
    final inicialNombre = nombres.isEmpty ? '' : nombres[0];
    final inicialApellido = apellidos.isEmpty ? '' : apellidos[0];
    return '$inicialNombre$inicialApellido'.toUpperCase();
  }
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.perfil, required this.iniciales, required this.subiendo});

  final PerfilUsuario perfil;
  final String iniciales;
  final bool subiendo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;

    if (perfil.fotoKey == null) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: colores.primaryContainer,
        child: Text(
          iniciales,
          style: TextStyle(color: colores.onPrimaryContainer, fontWeight: FontWeight.w700),
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(apiClientProvider).getJson(
            '/archivos/por-clave/url',
            parametros: {'objetoKey': perfil.fotoKey},
          ),
      builder: (context, snapshot) {
        final url = snapshot.data?['url'] as String?;
        if (snapshot.connectionState == ConnectionState.waiting || subiendo) {
          return CircleAvatar(
            radius: 34,
            backgroundColor: colores.primaryContainer,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (url == null) {
          return CircleAvatar(
            radius: 34,
            backgroundColor: colores.primaryContainer,
            child: Text(
              iniciales,
              style: TextStyle(color: colores.onPrimaryContainer, fontWeight: FontWeight.w700),
            ),
          );
        }
        return CircleAvatar(
          radius: 34,
          backgroundColor: colores.primaryContainer,
          backgroundImage: NetworkImage(url),
        );
      },
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            etiqueta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(child: Text(valor, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
