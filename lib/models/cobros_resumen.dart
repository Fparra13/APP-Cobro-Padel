/// Agregado de cobranza del grupo (vista `cobros_resumen` / SSOT local).
class CobrosResumen {
  final double montoTotalPendiente;
  final int jugadoresConDeuda;

  const CobrosResumen({
    required this.montoTotalPendiente,
    required this.jugadoresConDeuda,
  });

  static const zero = CobrosResumen(
    montoTotalPendiente: 0,
    jugadoresConDeuda: 0,
  );
}
