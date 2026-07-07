import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/repositories/partido_repository.dart';

ResumenJugador _resumen({
  required double saldo,
  double totalPendiente = 0,
}) {
  return ResumenJugador(
    jugador: Jugador(
      nombre: 'Test',
      saldoAcumulado: saldo,
      createdAt: DateTime(2026),
    ),
    saldoActual: saldo,
    partidosJugados: 1,
    totalPendiente: totalPendiente,
  );
}

void main() {
  test('saldo a favor no aparece como deuda en planilla', () {
    final r = _resumen(saldo: -50900, totalPendiente: 9000);
    expect(r.deudaVisible, 0);
    expect(r.tieneDeuda, isFalse);
    expect(r.creditoVisible, 50900);
    expect(r.tieneCredito, isTrue);
  });

  test('saldo deudor sin cobros abiertos sí aparece (ajuste manual)', () {
    final r = _resumen(saldo: 1400, totalPendiente: 0);
    expect(r.deudaVisible, 1400);
    expect(r.tieneDeuda, isTrue);
  });

  test('deuda visible = saldo_acumulado (no suma bruta por partido)', () {
    // Si saldo es 0 pero hay detalles impagos, la BD está desalineada;
    // la UI muestra saldo_acumulado como verdad.
    final r = _resumen(saldo: 0, totalPendiente: 1400);
    expect(r.deudaVisible, 0);
    expect(r.tieneDeuda, isFalse);
  });
}
