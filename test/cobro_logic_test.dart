import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_logic.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/services/calculation_service.dart';

void main() {
  group('CobroLogic.estadoPagoPartido', () {
    test('efectivo total liquida todo el saldo acumulado', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: 5000,
        cargo: 6000,
        montoPagadoOrganizador: 11000,
      );
      expect(r.pagado, isTrue);
      expect(r.montoPagado, 11000);
      expect(r.saldoNuevo, 0);
      expect(r.concepto, 'Encuentro pagado');
    });

    test('pago solo del partido no liquida deuda anterior', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: 5000,
        cargo: 6000,
        montoPagadoOrganizador: 6000,
      );
      expect(r.pagado, isTrue);
      expect(r.montoPagado, 6000);
      expect(r.saldoNuevo, 5000);
      expect(r.concepto, 'Encuentro pagado');
    });

    test('sin efectivo acumula deuda', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: 5000,
        cargo: 6000,
        montoPagadoOrganizador: 0,
      );
      expect(r.pagado, isFalse);
      expect(r.saldoNuevo, 11000);
      expect(r.concepto, 'Deuda acumulada');
    });

    test('pago parcial en efectivo', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: 0,
        cargo: 10000,
        montoPagadoOrganizador: 4000,
      );
      expect(r.pagado, isFalse);
      expect(r.saldoNuevo, 6000);
      expect(r.concepto, 'Pago parcial');
    });

    test('saldo a favor cubre todo sin efectivo', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: -8000,
        cargo: 6000,
        montoPagadoOrganizador: 0,
      );
      expect(r.pagado, isTrue);
      expect(r.saldoNuevo, lessThanOrEqualTo(0));
      expect(r.concepto, 'Encuentro cubierto con saldo a favor');
    });

    test('saldo a favor parcial + efectivo completa pago', () {
      final favor = CalculationService.saldoFavorAplicado(
        saldoAnterior: -3000,
        cargoPartido: 6000,
      );
      expect(favor, 3000);

      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: -3000,
        cargo: 6000,
        montoPagadoOrganizador: 3000,
      );
      expect(r.pagado, isTrue);
      expect(r.concepto, 'Encuentro pagado');
    });

    test('saldo a favor cubre partido sin efectivo y consume crédito', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: -8000,
        cargo: 6000,
        montoPagadoOrganizador: 0,
      );
      expect(r.pagado, isTrue);
      expect(r.montoPagado, 0);
      expect(r.saldoNuevo, -2000);
      expect(r.concepto, 'Encuentro cubierto con saldo a favor');
    });
  });

  group('CalculationService saldo a favor en partido', () {
    test('netoAPagarPartido descuenta crédito', () {
      expect(
        CalculationService.netoAPagarPartido(
          saldoAnterior: -8000,
          cargoPartido: 6000,
        ),
        0,
      );
      expect(
        CalculationService.netoAPagarPartido(
          saldoAnterior: -3000,
          cargoPartido: 6000,
        ),
        3000,
      );
    });

    test('pendientePartido sin deuda anterior positiva', () {
      expect(
        CalculationService.pendientePartido(
          saldoAnterior: 5000,
          cargoPartido: 6000,
          montoPagado: 0,
        ),
        6000,
      );
    });

    test('partido cubierto con saldo a favor y abono neto del cargo', () {
      expect(
        CobroLogic.obtenerPendientePartido(
          saldoAnteriorAlPartido: -5000,
          cargoPartido: 7500,
          montoPagadoEnPartido: 2500,
        ),
        0,
      );
      expect(
        CobroLogic.partidoEstaCerrado(
          saldoAnteriorAlPartido: -5000,
          cargoPartido: 7500,
          montoPagadoEnPartido: 2500,
        ),
        isTrue,
      );
    });
  });

  group('CobroLogic.totalPendientePartidosImpagos', () {
    test('no encadena deuda entre partidos (caso Francisco)', () {
      final total = CobroLogic.totalPendientePartidosImpagos(
        detallesImpagos: [
          (total: 8450.0, montoPagado: 0.0),
          (total: 9550.0, montoPagado: 0.0),
          (total: 8000.0, montoPagado: 0.0),
          (total: 8450.0, montoPagado: 0.0),
        ],
      );
      expect(total, 34450);
    });

    test('resta abonos parciales por partido', () {
      final total = CobroLogic.totalPendientePartidosImpagos(
        detallesImpagos: [
          (total: 8000.0, montoPagado: 3000.0),
          (total: 6000.0, montoPagado: 0.0),
        ],
      );
      expect(total, 11000);
    });
  });

  group('CobroLogic.estadoTrasEdicionConvocatoria', () {
    test('preserva confirmado si UI aún dice invitado', () {
      expect(
        CobroLogic.estadoTrasEdicionConvocatoria(
          prevEstado: EstadoConfirmacion.confirmado,
          inputEstado: EstadoConfirmacion.invitado,
        ),
        EstadoConfirmacion.confirmado,
      );
    });

    test('permite cambio manual del organizador a rechazado', () {
      expect(
        CobroLogic.estadoTrasEdicionConvocatoria(
          prevEstado: EstadoConfirmacion.confirmado,
          inputEstado: EstadoConfirmacion.rechazado,
        ),
        EstadoConfirmacion.rechazado,
      );
    });

    test('jugador nuevo usa estado del input', () {
      expect(
        CobroLogic.estadoTrasEdicionConvocatoria(
          prevEstado: null,
          inputEstado: EstadoConfirmacion.invitado,
        ),
        EstadoConfirmacion.invitado,
      );
    });
  });

  group('CobroLogic.pendienteEnCobro', () {
    test('incluye deuda anterior en el pendiente del cobro', () {
      expect(
        CobroLogic.pendienteEnCobro(
          saldoAnterior: 5000,
          cargoPartido: 8000,
          montoPagado: 0,
        ),
        13000,
      );
    });

    test('sin deuda anterior solo cargo menos abonado', () {
      expect(
        CobroLogic.pendienteEnCobro(
          saldoAnterior: 0,
          cargoPartido: 8000,
          montoPagado: 3000,
        ),
        5000,
      );
    });
  });

  group('CobroLogic.evaluarValidacionComprobante', () {
    test('doble validación se ignora', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: true,
        pendientePartido: 10000,
      );
      expect(d.accion, ComprobanteValidacionAccion.ignorarYaValidado);
    });

    test('ya pagado solo marca comprobante', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: true,
        comprobanteValidado: false,
        pendientePartido: 0,
      );
      expect(d.accion, ComprobanteValidacionAccion.soloMarcarComprobante);
    });

    test('pagado true con deuda neta pendiente aplica abono', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: true,
        comprobanteValidado: false,
        pendientePartido: 3500,
        montoPagoDeclarado: 10000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 10000);
    });

    test('pendiente real genera abono parcial', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: false,
        pendientePartido: 7000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 7000);
    });

    test('usa monto declarado por jugador si existe', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: false,
        pendientePartido: 10000,
        montoPagoDeclarado: 15000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 15000);
    });

    test('no confunde cargo pagado con deuda anterior pendiente', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: false,
        pendientePartido: 5000,
        montoPagoDeclarado: 5000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 5000);
    });

    test('abono mayor al partido conserva monto declarado completo', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: false,
        pendientePartido: 10000,
        montoPagoDeclarado: 20000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 20000);
    });

    test('rechazo explícito', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: false,
        pagado: false,
        comprobanteValidado: false,
        pendientePartido: 10000,
      );
      expect(d.accion, ComprobanteValidacionAccion.rechazar);
    });
  });

  group('CobroLogic.estadoPagoDetalle', () {
    test('deuda neta con saldo anterior positivo', () {
      final e = CobroLogic.estadoPagoDetalle(
        partidoId: 1,
        jugadorId: 'u1',
        cargoPartido: 6000,
        montoPagadoEnPartido: 0,
        snapshotSaldoAnterior: 5000,
      );
      expect(e.pendienteNeto, 11000);
      expect(e.tieneDeuda, isTrue);
      expect(e.partidoCerrado, isFalse);
      expect(e.pagoParcial, isFalse);
    });

    test('partido cerrado con crédito aplicado', () {
      final e = CobroLogic.estadoPagoDetalle(
        partidoId: 2,
        jugadorId: 'u2',
        cargoPartido: 6000,
        montoPagadoEnPartido: 0,
        snapshotSaldoAnterior: -8000,
      );
      expect(e.partidoCerrado, isTrue);
      expect(e.tieneDeuda, isFalse);
      expect(e.pendienteNeto, 0);
    });

    test('pago parcial neto', () {
      final e = CobroLogic.estadoPagoDetalle(
        partidoId: 3,
        jugadorId: 'u3',
        cargoPartido: 10000,
        montoPagadoEnPartido: 4000,
        snapshotSaldoAnterior: 0,
      );
      expect(e.pagoParcial, isTrue);
      expect(e.partidoCerrado, isFalse);
      expect(e.pendienteNeto, 6000);
    });

    test('sin snapshot lanza DatosInconsistentesException si se exige', () {
      expect(
        () => CobroLogic.estadoPagoDetalle(
          partidoId: 4,
          jugadorId: 'u4',
          cargoPartido: 5000,
          montoPagadoEnPartido: 0,
          snapshotSaldoAnterior: null,
          exigirSnapshot: true,
        ),
        throwsA(isA<DatosInconsistentesException>()),
      );
    });

    test('sin snapshot en UI usa saldo_anterior 0', () {
      final e = CobroLogic.estadoPagoDetalle(
        partidoId: 4,
        jugadorId: 'u4',
        cargoPartido: 5000,
        montoPagadoEnPartido: 0,
        snapshotSaldoAnterior: null,
      );
      expect(e.pendienteNeto, 5000);
      expect(e.partidoCerrado, isFalse);
    });
  });
}
