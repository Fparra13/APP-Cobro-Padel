import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_logic.dart';

/// Casos canónicos de Kloovi.
///
/// Convención en código/BD: saldo_acumulado > 0 = debe, < 0 = crédito a favor.
void main() {
  group('obtenerPendienteJugador / obtenerCreditoJugador', () {
    test('sin deuda ni crédito', () {
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: 0), 0);
      expect(CobroLogic.obtenerCreditoJugador(saldoAcumulado: 0), 0);
    });

    test('debe 6000', () {
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: 6000), 6000);
    });

    test('crédito 5000', () {
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: -5000), 0);
      expect(CobroLogic.obtenerCreditoJugador(saldoAcumulado: -5000), 5000);
    });
  });

  group('Escenario 1 — pago exacto', () {
    test('partido 10000, saldo 0, paga 10000 → saldo 0, partido cerrado', () {
      const saldoAnt = 0.0;
      const cargo = 10000.0;
      const pago = 10000.0;

      final saldoNuevo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldoAnt,
        cargoPartido: cargo,
        montoPagado: pago,
      );
      expect(saldoNuevo, 0);
      expect(
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoNuevo),
        0,
      );
      expect(
        CobroLogic.partidoEstaCerrado(
          saldoAnteriorAlPartido: saldoAnt,
          cargoPartido: cargo,
          montoPagadoEnPartido: pago,
        ),
        isTrue,
      );
    });
  });

  group('Escenario 2 — abono parcial', () {
    test('partido 10000, saldo 0, paga 4000 → debe 6000, partido abierto', () {
      const saldoAnt = 0.0;
      const cargo = 10000.0;
      const pago = 4000.0;

      final saldoNuevo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldoAnt,
        cargoPartido: cargo,
        montoPagado: pago,
      );
      expect(saldoNuevo, 6000);
      expect(
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoNuevo),
        6000,
      );
      expect(
        CobroLogic.obtenerPendientePartido(
          saldoAnteriorAlPartido: saldoAnt,
          cargoPartido: cargo,
          montoPagadoEnPartido: pago,
        ),
        6000,
      );
      expect(
        CobroLogic.partidoEstaCerrado(
          saldoAnteriorAlPartido: saldoAnt,
          cargoPartido: cargo,
          montoPagadoEnPartido: pago,
        ),
        isFalse,
      );
    });
  });

  group('Escenario 3 — pago mayor', () {
    test('partido 10000, saldo 0, paga 15000 → crédito 5000, partido cerrado', () {
      const saldoAnt = 0.0;
      const cargo = 10000.0;
      const pago = 15000.0;

      final saldoNuevo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldoAnt,
        cargoPartido: cargo,
        montoPagado: pago,
      );
      expect(saldoNuevo, -5000);
      expect(
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoNuevo),
        0,
      );
      expect(
        CobroLogic.obtenerCreditoJugador(saldoAcumulado: saldoNuevo),
        5000,
      );
      expect(
        CobroLogic.partidoEstaCerrado(
          saldoAnteriorAlPartido: saldoAnt,
          cargoPartido: cargo,
          montoPagadoEnPartido: pago,
        ),
        isTrue,
      );
    });
  });

  group('Escenario 4 — crédito + nuevo partido (caso canónico Kloovi)', () {
    test('crédito 5000 + partido 10000 → debe 5000', () {
      const saldoAnt = -5000.0; // crédito
      const cargo = 10000.0;
      const pago = 0.0;

      final saldoNuevo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldoAnt,
        cargoPartido: cargo,
        montoPagado: pago,
      );
      expect(saldoNuevo, 5000);
      expect(
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoNuevo),
        5000,
      );
      expect(
        CobroLogic.obtenerPendientePartido(
          saldoAnteriorAlPartido: saldoAnt,
          cargoPartido: cargo,
          montoPagadoEnPartido: pago,
        ),
        5000,
      );
    });

    test('misma pantalla: jugador y partido coinciden', () {
      const saldoAnt = -5000.0;
      const cargo = 10000.0;
      const pago = 0.0;
      final saldoNuevo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldoAnt,
        cargoPartido: cargo,
        montoPagado: pago,
      );
      final deudaJugador =
          CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoNuevo);
      final deudaPartido = CobroLogic.obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAnt,
        cargoPartido: cargo,
        montoPagadoEnPartido: pago,
      );
      expect(deudaJugador, deudaPartido);
      expect(deudaJugador, 5000);
    });
  });

  group('Matriz canónica — cargo sin pago', () {
    const cargo = 10000.0;

    test('saldo 0 + cargo 10.000 → debe 10.000', () {
      final saldo = CobroLogic.saldoTrasCargo(
        saldoAcumulado: 0,
        cargoPartido: cargo,
      );
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 10000);
    });

    test('saldo 5.000 + cargo 10.000 → debe 15.000', () {
      final saldo = CobroLogic.saldoTrasCargo(
        saldoAcumulado: 5000,
        cargoPartido: cargo,
      );
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 15000);
    });

    test('saldo -5.000 (crédito) + cargo 10.000 → debe 5.000', () {
      final saldo = CobroLogic.saldoTrasCargo(
        saldoAcumulado: -5000,
        cargoPartido: cargo,
      );
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 5000);
      expect(
        CobroLogic.obtenerPendientePartido(
          saldoAnteriorAlPartido: -5000,
          cargoPartido: cargo,
          montoPagadoEnPartido: 0,
        ),
        5000,
      );
    });

    test('saldo -15.000 (crédito) + cargo 10.000 → crédito 5.000', () {
      final saldo = CobroLogic.saldoTrasCargo(
        saldoAcumulado: -15000,
        cargoPartido: cargo,
      );
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 0);
      expect(CobroLogic.obtenerCreditoJugador(saldoAcumulado: saldo), 5000);
    });
  });

  group('saldoAnteriorAlPartido — snapshot inmutable', () {
    test('usa snapshot guardado', () {
      expect(
        CobroLogic.saldoAnteriorAlPartido(snapshotHistorico: -5000),
        -5000,
      );
    });

    test('sin snapshot devuelve 0 (no recalcular en UI)', () {
      expect(CobroLogic.saldoAnteriorAlPartido(snapshotHistorico: null), 0);
    });
  });

  group('pendienteNetoDetalle — lectura con snapshot', () {
    test('crédito + cargo usa pendiente neto, no bruto', () {
      expect(
        CobroLogic.pendienteNetoDetalle(
          partidoId: 1,
          jugadorId: 'u1',
          cargoPartido: 10000,
          montoPagadoEnPartido: 0,
          snapshotSaldoAnterior: -5000,
        ),
        5000,
      );
    });

    test('sin snapshot lanza DatosInconsistentesException', () {
      expect(
        () => CobroLogic.pendienteNetoDetalle(
          partidoId: 1,
          jugadorId: 'u1',
          cargoPartido: 10000,
          montoPagadoEnPartido: 0,
          snapshotSaldoAnterior: null,
        ),
        throwsA(isA<DatosInconsistentesException>()),
      );
    });
  });

  group('Pagos sobre saldo existente', () {
    test('pago parcial sobre deuda 10.000', () {
      final saldo = CobroLogic.saldoTrasPago(
        saldoAcumulado: 10000,
        montoPagado: 4000,
      );
      expect(saldo, 6000);
    });

    test('pago mayor genera crédito', () {
      final saldo = CobroLogic.saldoTrasPago(
        saldoAcumulado: 10000,
        montoPagado: 15000,
      );
      expect(saldo, -5000);
      expect(CobroLogic.obtenerCreditoJugador(saldoAcumulado: saldo), 5000);
    });

    test('varios pagos acumulados', () {
      var saldo = CobroLogic.saldoTrasCargo(saldoAcumulado: 0, cargoPartido: 10000);
      saldo = CobroLogic.saldoTrasPago(saldoAcumulado: saldo, montoPagado: 3000);
      saldo = CobroLogic.saldoTrasPago(saldoAcumulado: saldo, montoPagado: 2000);
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 5000);
    });
  });

  group('Escenario 5 — tres partidos con reparto', () {
    test('deuda encadenada y pagos parciales', () {
      // Partido 1: debe 4000
      var saldo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: 0,
        cargoPartido: 4000,
        montoPagado: 0,
      );
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 4000);

      // Partido 2: +6000 → debe 10000
      saldo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldo,
        cargoPartido: 6000,
        montoPagado: 0,
      );
      expect(
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo),
        10000,
      );

      // Abono global 3000 → debe 7000
      saldo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldo,
        cargoPartido: 0,
        montoPagado: 3000,
      );
      expect(CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo), 7000);

      // Partido 3: +5000 → debe 12000
      saldo = CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldo,
        cargoPartido: 5000,
        montoPagado: 0,
      );
      expect(
        CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldo),
        12000,
      );
    });
  });

  group('obtenerPendienteGrupo', () {
    test('suma deuda neta de jugadores', () {
      expect(
        CobroLogic.obtenerPendienteGrupo(
          saldosAcumulados: [5000, 0, -3000, 2000],
        ),
        7000,
      );
    });
  });
}
