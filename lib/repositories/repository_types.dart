/// Input unificado para costos variables (IDs de jugador como String).
typedef CostoVariableInput = ({
  String concepto,
  double montoTotal,
  List<String> jugadores,
  String? comprobantePath,
  String? comprobanteUrl,
  String? iconKey,
});
