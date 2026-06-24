class Jugador {
  final int? id;
  final String nombre;
  final bool activo;
  final double saldoAcumulado;
  final String? telefono;
  final DateTime createdAt;

  const Jugador({
    this.id,
    required this.nombre,
    this.activo = true,
    this.saldoAcumulado = 0,
    this.telefono,
    required this.createdAt,
  });

  Jugador copyWith({
    int? id,
    String? nombre,
    bool? activo,
    double? saldoAcumulado,
    String? telefono,
    DateTime? createdAt,
  }) {
    return Jugador(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      saldoAcumulado: saldoAcumulado ?? this.saldoAcumulado,
      telefono: telefono ?? this.telefono,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'activo': activo ? 1 : 0,
        'saldo_acumulado': saldoAcumulado,
        'telefono': telefono,
        'created_at': createdAt.toIso8601String(),
      };

  factory Jugador.fromMap(Map<String, dynamic> map) => Jugador(
        id: map['id'] as int?,
        nombre: map['nombre'] as String,
        activo: (map['activo'] as int? ?? 1) == 1,
        saldoAcumulado: (map['saldo_acumulado'] as num?)?.toDouble() ?? 0,
        telefono: map['telefono'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
