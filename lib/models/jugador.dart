class Jugador {
  final int? id;
  /// UUID en Supabase (`profiles.id`). Null en SQLite local.
  final String? supabaseId;
  final String nombre;
  final bool activo;
  final double saldoAcumulado;
  final String? telefono;
  final String? fotoPath;
  /// URL pública en Supabase Storage.
  final String? fotoUrl;
  final DateTime createdAt;

  const Jugador({
    this.id,
    this.supabaseId,
    required this.nombre,
    this.activo = true,
    this.saldoAcumulado = 0,
    this.telefono,
    this.fotoPath,
    this.fotoUrl,
    required this.createdAt,
  });

  /// Identificador principal según origen (Supabase o SQLite).
  String? get remoteId => supabaseId;

  Jugador copyWith({
    int? id,
    String? supabaseId,
    String? nombre,
    bool? activo,
    double? saldoAcumulado,
    String? telefono,
    String? fotoPath,
    String? fotoUrl,
    bool clearFoto = false,
    DateTime? createdAt,
  }) {
    return Jugador(
      id: id ?? this.id,
      supabaseId: supabaseId ?? this.supabaseId,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      saldoAcumulado: saldoAcumulado ?? this.saldoAcumulado,
      telefono: telefono ?? this.telefono,
      fotoPath: clearFoto ? null : (fotoPath ?? this.fotoPath),
      fotoUrl: clearFoto ? null : (fotoUrl ?? this.fotoUrl),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'activo': activo ? 1 : 0,
        'saldo_acumulado': saldoAcumulado,
        'telefono': telefono,
        'foto_path': fotoPath,
        'created_at': createdAt.toIso8601String(),
      };

  factory Jugador.fromMap(Map<String, dynamic> map) => Jugador(
        id: map['id'] as int?,
        nombre: map['nombre'] as String,
        activo: (map['activo'] as int? ?? 1) == 1,
        saldoAcumulado: (map['saldo_acumulado'] as num?)?.toDouble() ?? 0,
        telefono: map['telefono'] as String?,
        fotoPath: map['foto_path'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  factory Jugador.fromSupabaseMap(Map<String, dynamic> map) => Jugador(
        supabaseId: map['id'] as String,
        nombre: map['nombre'] as String,
        activo: map['activo'] as bool? ?? true,
        saldoAcumulado: (map['saldo_acumulado'] as num?)?.toDouble() ?? 0,
        telefono: map['telefono'] as String?,
        fotoUrl: map['foto_url'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toSupabaseMap() => {
        if (supabaseId != null) 'id': supabaseId,
        'nombre': nombre,
        'activo': activo,
        'saldo_acumulado': saldoAcumulado,
        'telefono': telefono,
        'foto_url': fotoUrl,
      };
}
