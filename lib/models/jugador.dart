class Jugador {
  final int? id;
  final String nombre;
  final bool activo;
  final double saldoAcumulado;
  final String? telefono;
  final String? fotoPath;
  final DateTime createdAt;

  const Jugador({
    this.id,
    required this.nombre,
    this.activo = true,
    this.saldoAcumulado = 0,
    this.telefono,
    this.fotoPath,
    required this.createdAt,
  });

  Jugador copyWith({
    int? id,
    String? nombre,
    bool? activo,
    double? saldoAcumulado,
    String? telefono,
    String? fotoPath,
    bool clearFoto = false,
    DateTime? createdAt,
  }) {
    return Jugador(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      saldoAcumulado: saldoAcumulado ?? this.saldoAcumulado,
      telefono: telefono ?? this.telefono,
      fotoPath: clearFoto ? null : (fotoPath ?? this.fotoPath),
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
}
