/// Resultado de unirse a un organizador con código de grupo.
class UnirseGrupoResult {
  final String organizadorId;
  final String nombre;
  final String codigo;
  final bool yaEstaba;
  /// True si ya tenía otro organizador y esta unión no es un rejoin activo.
  final bool esCuentaAdicional;

  const UnirseGrupoResult({
    required this.organizadorId,
    required this.nombre,
    required this.codigo,
    required this.yaEstaba,
    this.esCuentaAdicional = false,
  });

  factory UnirseGrupoResult.fromJson(Map<String, dynamic> json) {
    return UnirseGrupoResult(
      organizadorId: '${json['organizador_id'] ?? ''}',
      nombre: (json['nombre'] as String?)?.trim().isNotEmpty == true
          ? (json['nombre'] as String).trim()
          : 'Organizador',
      codigo: (json['codigo'] as String?)?.trim() ?? '',
      yaEstaba: json['ya_estaba'] == true,
      esCuentaAdicional: json['es_cuenta_adicional'] == true,
    );
  }
}

/// Organizador al que el jugador ya está vinculado.
class MiOrganizadorGrupo {
  final String id;
  final String nombre;
  final String? fotoUrl;
  final DateTime? unidoEn;

  const MiOrganizadorGrupo({
    required this.id,
    required this.nombre,
    this.fotoUrl,
    this.unidoEn,
  });

  factory MiOrganizadorGrupo.fromJson(Map<String, dynamic> json) {
    DateTime? unido;
    final raw = json['unido_en'];
    if (raw is String) {
      unido = DateTime.tryParse(raw);
    }
    return MiOrganizadorGrupo(
      id: '${json['id'] ?? ''}',
      nombre: (json['nombre'] as String?)?.trim().isNotEmpty == true
          ? (json['nombre'] as String).trim()
          : 'Organizador',
      fotoUrl: json['foto_url'] as String?,
      unidoEn: unido,
    );
  }
}
