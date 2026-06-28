class CostoVariable {
  final int? id;
  final int partidoId;
  final String concepto;
  final double montoTotal;
  final String? comprobantePath;

  const CostoVariable({
    this.id,
    required this.partidoId,
    required this.concepto,
    required this.montoTotal,
    this.comprobantePath,
  });

  String? get comprobanteUrl => comprobantePath;

  Map<String, dynamic> toMap() => {
        'id': id,
        'partido_id': partidoId,
        'concepto': concepto,
        'monto_total': montoTotal,
        'comprobante_path': comprobantePath,
      };

  factory CostoVariable.fromMap(Map<String, dynamic> map) => CostoVariable(
        id: map['id'] as int?,
        partidoId: map['partido_id'] as int,
        concepto: map['concepto'] as String,
        montoTotal: (map['monto_total'] as num).toDouble(),
        comprobantePath: map['comprobante_path'] as String?,
      );

  factory CostoVariable.fromSupabaseMap(Map<String, dynamic> map) =>
      CostoVariable(
        id: (map['id'] as num).toInt(),
        partidoId: (map['partido_id'] as num).toInt(),
        concepto: map['concepto'] as String,
        montoTotal: (map['monto_total'] as num).toDouble(),
        comprobantePath: map['comprobante_url'] as String?,
      );
}

class AsignacionCostoVariable {
  final int? id;
  final int costoVariableId;
  final int jugadorId;
  final String? jugadorSupabaseId;
  final double monto;

  const AsignacionCostoVariable({
    this.id,
    required this.costoVariableId,
    this.jugadorId = 0,
    this.jugadorSupabaseId,
    required this.monto,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'costo_variable_id': costoVariableId,
        'jugador_id': jugadorId,
        'monto': monto,
      };

  factory AsignacionCostoVariable.fromMap(Map<String, dynamic> map) =>
      AsignacionCostoVariable(
        id: map['id'] as int?,
        costoVariableId: map['costo_variable_id'] as int,
        jugadorId: map['jugador_id'] as int,
        monto: (map['monto'] as num).toDouble(),
      );

  factory AsignacionCostoVariable.fromSupabaseMap(Map<String, dynamic> map) =>
      AsignacionCostoVariable(
        id: (map['id'] as num?)?.toInt(),
        costoVariableId: (map['costo_variable_id'] as num).toInt(),
        jugadorSupabaseId: map['jugador_id'] as String,
        monto: (map['monto'] as num).toDouble(),
      );
}
