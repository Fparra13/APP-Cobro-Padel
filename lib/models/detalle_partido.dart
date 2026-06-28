class DetallePartido {
  final int? id;
  final int partidoId;
  final int jugadorId;
  /// UUID del jugador en Supabase.
  final String? jugadorSupabaseId;
  final bool asistio;
  final double prorrateoFijo;
  final double totalVariables;
  final double total;
  final bool pagado;
  final double montoPagado;
  final String? nombreJugador;

  const DetallePartido({
    this.id,
    required this.partidoId,
    this.jugadorId = 0,
    this.jugadorSupabaseId,
    this.asistio = true,
    this.prorrateoFijo = 0,
    this.totalVariables = 0,
    this.total = 0,
    this.pagado = false,
    this.montoPagado = 0,
    this.nombreJugador,
  });

  bool get pagoParcial => montoPagado > 0 && !pagado;

  DetallePartido copyWith({
    int? id,
    int? partidoId,
    int? jugadorId,
    bool? asistio,
    double? prorrateoFijo,
    double? totalVariables,
    double? total,
    bool? pagado,
    double? montoPagado,
    String? nombreJugador,
  }) {
    return DetallePartido(
      id: id ?? this.id,
      partidoId: partidoId ?? this.partidoId,
      jugadorId: jugadorId ?? this.jugadorId,
      asistio: asistio ?? this.asistio,
      prorrateoFijo: prorrateoFijo ?? this.prorrateoFijo,
      totalVariables: totalVariables ?? this.totalVariables,
      total: total ?? this.total,
      pagado: pagado ?? this.pagado,
      montoPagado: montoPagado ?? this.montoPagado,
      nombreJugador: nombreJugador ?? this.nombreJugador,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'partido_id': partidoId,
        'jugador_id': jugadorId,
        'asistio': asistio ? 1 : 0,
        'prorrateo_fijo': prorrateoFijo,
        'total_variables': totalVariables,
        'total': total,
        'pagado': pagado ? 1 : 0,
        'monto_pagado': montoPagado,
      };

  factory DetallePartido.fromMap(Map<String, dynamic> map) => DetallePartido(
        id: map['id'] as int?,
        partidoId: map['partido_id'] as int,
        jugadorId: map['jugador_id'] as int,
        asistio: (map['asistio'] as int? ?? 1) == 1,
        prorrateoFijo: (map['prorrateo_fijo'] as num?)?.toDouble() ?? 0,
        totalVariables: (map['total_variables'] as num?)?.toDouble() ?? 0,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        pagado: (map['pagado'] as int? ?? 0) == 1,
        montoPagado: (map['monto_pagado'] as num?)?.toDouble() ?? 0,
        nombreJugador: map['nombre_jugador'] as String?,
      );

  factory DetallePartido.fromSupabaseMap(
    Map<String, dynamic> map, {
    String? nombreJugador,
  }) =>
      DetallePartido(
        id: (map['id'] as num?)?.toInt(),
        partidoId: (map['partido_id'] as num).toInt(),
        jugadorSupabaseId: map['jugador_id'] as String,
        asistio: map['asistio'] as bool? ?? true,
        prorrateoFijo: (map['prorrateo_fijo'] as num?)?.toDouble() ?? 0,
        totalVariables: (map['total_variables'] as num?)?.toDouble() ?? 0,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        pagado: map['pagado'] as bool? ?? false,
        montoPagado: (map['monto_pagado'] as num?)?.toDouble() ?? 0,
        nombreJugador: nombreJugador,
      );
}
