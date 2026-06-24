import 'package:flutter_test/flutter_test.dart';
import 'package:padel_cobro/services/calculation_service.dart';

void main() {
  test('prorrateo fijo divide cancha y pelotas entre asistentes', () {
    final prorrateo = CalculationService.prorrateoFijo(
      costoCancha: 20000,
      costoPelotas: 4000,
      cantidadAsistentes: 4,
    );
    expect(prorrateo, 6000);
  });

  test('total jugador acumula deuda si no paga', () {
    final total = CalculationService.totalJugador(
      saldoAnterior: 5000,
      prorrateoFijo: 6000,
      totalVariables: 3000,
      pagado: false,
    );
    expect(total, 14000);
  });

  test('total jugador queda en cero si pagó', () {
    final total = CalculationService.totalJugador(
      saldoAnterior: 5000,
      prorrateoFijo: 6000,
      totalVariables: 3000,
      pagado: true,
    );
    expect(total, 0);
  });
}
