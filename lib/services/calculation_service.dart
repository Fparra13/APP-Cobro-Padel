import '../utils/formatters.dart';

class CalculationService {
  static double prorratear(double total, int cantidad) {
    if (cantidad <= 0) return 0;
    return roundMoney(total / cantidad).toDouble();
  }

  static double prorrateoFijo({
    required double costoCancha,
    required double costoPelotas,
    required int cantidadAsistentes,
  }) {
    return prorratear(costoCancha, cantidadAsistentes) +
        prorratear(costoPelotas, cantidadAsistentes);
  }

  static double prorrateoCancha({
    required double costoCancha,
    required int cantidadAsistentes,
  }) =>
      prorratear(costoCancha, cantidadAsistentes);

  static double prorrateoPelotas({
    required double costoPelotas,
    required int cantidadAsistentes,
  }) =>
      prorratear(costoPelotas, cantidadAsistentes);

  /// SA = saldo anterior + cargo − abono. Puede ser negativo (saldo a favor).
  static double saldoDespuesPago({
    required double saldoAnterior,
    required double cargoPartido,
    required double montoPagado,
  }) {
    final totalDebido = roundMoney(saldoAnterior + cargoPartido).toDouble();
    final pagado = roundMoney(montoPagado).toDouble();
    return roundMoney(totalDebido - pagado).toDouble();
  }

  /// Total a pagar antes de abonos (puede ser menor que el cargo si hay saldo a favor).
  static double totalDebido({
    required double saldoAnterior,
    required double cargoPartido,
  }) =>
      roundMoney(saldoAnterior + cargoPartido).toDouble();

  /// Monto del saldo a favor que se descuenta del cargo del partido.
  static double saldoFavorAplicado({
    required double saldoAnterior,
    required double cargoPartido,
  }) {
    if (saldoAnterior >= 0 || cargoPartido <= 0) return 0;
    final credito = -saldoAnterior;
    return roundMoney(
      credito > cargoPartido ? cargoPartido : credito,
    ).toDouble();
  }

  /// Lo que el jugador debe transferir en efectivo (nunca negativo).
  static double totalATransferir({
    required double saldoAnterior,
    required double cargoPartido,
    required double montoPagado,
  }) {
    final restante = saldoDespuesPago(
      saldoAnterior: saldoAnterior,
      cargoPartido: cargoPartido,
      montoPagado: montoPagado,
    );
    return restante > 0 ? restante : 0;
  }

  static double totalJugador({
    required double saldoAnterior,
    required double prorrateoFijo,
    required double totalVariables,
    required bool pagado,
  }) {
    final cargo = prorrateoFijo + totalVariables;
    if (pagado) return 0;
    return roundMoney(saldoAnterior + cargo).toDouble();
  }

  static double cargoPartido({
    required double prorrateoFijo,
    required double totalVariables,
  }) =>
      roundMoney(prorrateoFijo + totalVariables).toDouble();
}
