import 'package:flutter_test/flutter_test.dart';
import 'package:padel_cobro/domain/cobro_logic.dart';
import 'package:padel_cobro/models/estado_partido.dart';
import 'package:padel_cobro/services/calculation_service.dart';

void main() {
  group('CobroLogic.estadoPagoPartido', () {
    test('efectivo total deja saldo en cero y pagado', () {
      final r = CobroLogic.estadoPagoPartido(
        saldoAnterior: 5000,
        cargo: 6000,
        montoPagadoOrganizador: 11000,
      );
      expect(r.pagado, isTrue);
      expect(r.montoPagado, 11000);
      expect(r.saldoNuevo, 0);
      expect(r.concepto, 'Partido pagado');
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
      expect(r.concepto, 'Partido cubierto con saldo a favor');
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
      expect(r.concepto, 'Partido pagado');
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
        pendienteEnCobro: 10000,
      );
      expect(d.accion, ComprobanteValidacionAccion.ignorarYaValidado);
    });

    test('ya pagado solo marca comprobante', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: true,
        comprobanteValidado: false,
        pendienteEnCobro: 0,
      );
      expect(d.accion, ComprobanteValidacionAccion.soloMarcarComprobante);
    });

    test('pendiente real genera abono parcial', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: false,
        pendienteEnCobro: 7000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 7000);
    });

    test('usa monto declarado por jugador si existe', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: true,
        pagado: false,
        comprobanteValidado: false,
        pendienteEnCobro: 10000,
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
        pendienteEnCobro: 5000,
        montoPagoDeclarado: 5000,
      );
      expect(d.accion, ComprobanteValidacionAccion.abonarPendiente);
      expect(d.abono, 5000);
    });

    test('rechazo explícito', () {
      final d = CobroLogic.evaluarValidacionComprobante(
        aprobado: false,
        pagado: false,
        comprobanteValidado: false,
        pendienteEnCobro: 10000,
      );
      expect(d.accion, ComprobanteValidacionAccion.rechazar);
    });
  });
}
