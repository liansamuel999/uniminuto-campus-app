/// Perfil del usuario autenticado tal como lo devuelve `GET /api/v1/mi-perfil` (§7.7).
class PerfilUsuario {
  const PerfilUsuario({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.correo,
    required this.roles,
    this.documento,
    this.codigoInstitucional,
    this.fotoKey,
    this.estado = 'ACTIVO',
    this.programa,
  });

  final String id;
  final String nombres;
  final String apellidos;
  final String correo;
  final List<String> roles;
  final String? documento;
  final String? codigoInstitucional;
  final String? fotoKey;
  final String estado;
  final ProgramaResumen? programa;

  String get nombreCompleto => '$nombres $apellidos'.trim();

  static PerfilUsuario fromJson(Map<String, dynamic> json) {
    final programaJson = json['programa'];
    return PerfilUsuario(
      id: '${json['id']}',
      nombres: '${json['nombres'] ?? ''}',
      apellidos: '${json['apellidos'] ?? ''}',
      correo: '${json['correo'] ?? ''}',
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((rol) => '$rol')
          .toList(growable: false),
      documento: json['documento'] as String?,
      codigoInstitucional: json['codigoInstitucional'] as String?,
      fotoKey: json['fotoKey'] as String?,
      estado: '${json['estado'] ?? 'ACTIVO'}',
      programa: programaJson is Map<String, dynamic>
          ? ProgramaResumen(
              id: '${programaJson['id']}',
              nombre: '${programaJson['nombre'] ?? ''}',
            )
          : null,
    );
  }
}

class ProgramaResumen {
  const ProgramaResumen({required this.id, required this.nombre});

  final String id;
  final String nombre;
}
