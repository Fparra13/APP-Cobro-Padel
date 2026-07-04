import '../models/estado_partido.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';

/// Resultado de calcular pago al guardar/completar un partido.
class EstadoPagoPartidoResult {
  final double montoPagado;
  final bool pagado;
  final String concepto;
  final double saldoNuevo;

  const EstadoPagoPartidoResult({
    required this.montoPagado,
    required this.pagado,
    required this.concepto,
    required this.saldoNuevo,
  });
}

/// Decisión al validar un comprobante de pago.
enum ComprobanteValidacionAccion {
  rechazar,
  ignorarYaValidado,
  soloMarcarComprobante,
  abonarPendiente,
}

class ComprobanteValidacionDecision {
  final ComprobanteValidacionAccion accion;
  final double abono;

  const ComprobanteValidacionDecision({
    required this.accion,
    this.abono = 0,
  });
}

/// Lógica pura de cobros/convocatorias compartida por repositorios y tests.
class CobroLogic {
  CobroLogic._();

  static EstadoPagoPartidoResult estadoPagoPartido({
    required double saldoAnterior,
    required double cargo,
    required double montoPagadoOrganizador,
  }) {
    final montoPagado = roundMoney(montoPagadoOrganizador).toDouble();
    final saldoNuevo = CalculationService.saldoDespuesPago(
      saldoAnterior: saldoAnterior,
      cargoPartido: cargo,
      montoPagado: montoPagado,
    );
    final favorAplicado = CalculationService.saldoFavorAplicado(
      saldoAnterior: saldoAnterior,
      cargoPartido: cargo,
    );
    final pagado = saldoNuevo <= 0;
    final concepto = pagado
        ? (montoPagado == 0 && favorAplicado > 0
            ? 'Partido cubierto con saldo a favor'
            : 'Partido pagado')
        : montoPagado > 0
            ? 'Pago parcial'
            : 'Deuda acumulada';
    return EstadoPagoPartidoResult(
      montoPagado: montoPagado,
      pagado: pagado,
      concepto: concepto,
      saldoNuevo: saldoNuevo,
    );
  }

  static EstadoConfirmacion estadoTrasEdicionConvocatoria({
    EstadoConfirmacion? prevEstado,
    required EstadoConfirmacion inputEstado,
  }) {
    if (prevEstado == null) return inputEstado;
    if (prevEstado != EstadoConfirmacion.invitado &&
        inputEstado == EstadoConfirmacion.invitado) {
      return prevEstado;
    }
    return inputEstado;
  }

  /// Pendiente real en un cobro: deuda anterior + cargo del partido − abonado.
  static double pendienteEnCobro({
    required double saldoAnterior,
    required double cargoPartido,
    required double montoPagado,
  }) {
    final restante = CalculationService.saldoDespuesPago(
      saldoAnterior: saldoAnterior,
      cargoPartido: cargoPartido,
      montoPagado: montoPagado,
    );
    return restante > 0.005 ? roundMoney(restante).toDouble() : 0;
  }

  static ComprobanteValidacionDecision evaluarValidacionComprobante({
    required bool aprobado,
    required bool pagado,
    required bool comprobanteValidado,
    required double pendienteEnCobro,
    double? montoPagoDeclarado,
  }) {
    if (!aprobado) {
      return const ComprobanteValidacionDecision(
        accion: ComprobanteValidacionAccion.rechazar,
      );
    }
    if (comprobanteValidado) {
      return const ComprobanteValidacionDecision(
        accion: ComprobanteValidacionAccion.ignorarYaValidado,
      );
    }
    if (pagado || pendienteEnCobro <= 0.005) {
      return const ComprobanteValidacionDecision(
        accion: ComprobanteValidacionAccion.soloMarcarComprobante,
      );
    }
    final declarado = montoPagoDeclarado != null && montoPagoDeclarado > 0
        ? roundMoney(montoPagoDeclarado).toDouble()
        : pendienteEnCobro;
    return ComprobanteValidacionDecision(
      accion: ComprobanteValidacionAccion.abonarPendiente,
      abono: declarado,
    );
  }

  static String conceptoValidacionOrganizador({required bool esAbono}) =>
      esAbono ? 'Abono validado por organizador' : 'Pago validado por organizador';
}
