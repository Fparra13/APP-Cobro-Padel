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
}

class AsignacionCostoVariable {
  final int? id;
  final int costoVariableId;
  final int jugadorId;
  final double monto;

  const AsignacionCostoVariable({
    this.id,
    required this.costoVariableId,
    required this.jugadorId,
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
}
