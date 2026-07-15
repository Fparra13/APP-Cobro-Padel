import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_logic.dart';
import 'package:matchpay/services/calculation_service.dart';

/// Documenta el bug: fecha de historial del encuentro no puede quedar detrás
/// del abono que creó el saldo a favor.
void main() {
  test('cargo con saldo a favor reduce el crédito en saldoNuevo', () {
    const saldoAnterior = -50000.0; // a favor
    const cargo = 12000.0;
    final pago = CobroLogic.estadoPagoPartido(
      saldoAnterior: saldoAnterior,
      cargo: cargo,
      montoPagadoOrganizador: 0,
    );

    expect(pago.pagado, isTrue);
    expect(pago.montoPagado, 0);
    expect(pago.saldoNuevo, -38000);
    expect(
      CalculationService.saldoFavorAplicado(
        saldoAnterior: saldoAnterior,
        cargoPartido: cargo,
      ),
      12000,
    );
  });

  test(
    'último movimiento por id gana aunque fecha del partido sea anterior',
    () {
      // Simula filas de saldos_historicos ya insertadas.
      final rows = <({int id, DateTime fecha, double saldoNuevo})>[
        (
          id: 10,
          fecha: DateTime(2026, 7, 13, 10),
          saldoNuevo: -50000, // abono / crédito
        ),
        (
          id: 11,
          fecha: DateTime(2026, 7, 1, 20), // fecha partido antigua
          saldoNuevo: -38000, // cargo cubierto con favor
        ),
        (
          id: 12,
          fecha: DateTime(2026, 7, 2, 20),
          saldoNuevo: -26000,
        ),
      ];

      // Bug anterior: ORDER BY fecha DESC → -50000
      rows.sort((a, b) {
        final cmp = b.fecha.compareTo(a.fecha);
        if (cmp != 0) return cmp;
        return b.id.compareTo(a.id);
      });
      expect(rows.first.saldoNuevo, -50000);

      // Fix: ORDER BY id DESC → -26000
      rows.sort((a, b) => b.id.compareTo(a.id));
      expect(rows.first.saldoNuevo, -26000);
    },
  );
}
