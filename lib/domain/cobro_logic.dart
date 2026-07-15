import '../models/estado_partido.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';

/// Datos de cobro incoherentes (p. ej. falta snapshot en historial).
class DatosInconsistentesException implements Exception {
  final String message;

  const DatosInconsistentesException(this.message);

  @override
  String toString() => message;
}

/// Estado de cobro de un detalle (lectura). Fuente: snapshot + CobroLogic.
class EstadoPagoDetalle {
  final double pendienteNeto;
  final bool partidoCerrado;
  final double saldoRestanteTrasPartido;
  final double montoPagadoEnPartido;

  const EstadoPagoDetalle({
    required this.pendienteNeto,
    required this.partidoCerrado,
    required this.saldoRestanteTrasPartido,
    required this.montoPagadoEnPartido,
  });

  bool get tieneDeuda => pendienteNeto > 0.005;

  bool get pagoParcial =>
      !partidoCerrado && montoPagadoEnPartido > 0.005;
}

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
    final pagado = CalculationService.partidoCubierto(
      saldoAnterior: saldoAnterior,
      cargoPartido: cargo,
      montoPagado: montoPagado,
    );
    final concepto = pagado
        ? (montoPagado == 0 && favorAplicado > 0
            ? 'Encuentro cubierto con saldo a favor'
            : 'Encuentro pagado')
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

  /// Pendiente real en un cobro: saldo anterior + cargo del partido − abonado.
  ///
  /// Preferir [obtenerPendientePartido] en código nuevo.
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

  // --- Single Source of Truth (lectura) ---
  //
  // Dueño de la deuda: `organizador_jugadores.saldo_acumulado` por cuenta
  // (jugador ↔ organizador). > 0 debe a ese org; < 0 crédito solo con ese org.
  // `saldos_historicos` (con organizador_id) audita cómo se llegó a ese saldo.
  //
  // INVARIANTE multi-org: NUNCA netear. Crédito con Org A no reduce deuda
  // con Org B. Home = suma de deudas > 0 únicamente ([totalDeudaHomeSinNetear]).
  //
  // Regla: ninguna pantalla, modelo ni SQL debe calcular deuda con
  // `total - monto_pagado` sin pasar por estas funciones.

  /// Cuánto debe el jugador en UNA cuenta (con un organizador).
  ///
  /// Fuente: [saldoAcumulado] de `organizador_jugadores` (no global).
  static double obtenerPendienteJugador({required double saldoAcumulado}) {
    return saldoAcumulado > 0.005
        ? roundMoney(saldoAcumulado).toDouble()
        : 0;
  }

  /// Crédito a favor del jugador en UNA cuenta (positivo).
  static double obtenerCreditoJugador({required double saldoAcumulado}) {
    return saldoAcumulado < -0.005
        ? roundMoney(-saldoAcumulado).toDouble()
        : 0;
  }

  /// Total para home del jugador: suma solo saldos > 0.
  ///
  /// **No netea** créditos de otras cuentas. Pasar saldos de cada
  /// organizador (p. ej. desde `get_mis_cuentas_saldo`).
  static double totalDeudaHomeSinNetear({
    required Iterable<double> saldosPorOrganizador,
  }) {
    var total = 0.0;
    for (final saldo in saldosPorOrganizador) {
      total += obtenerPendienteJugador(saldoAcumulado: saldo);
    }
    return roundMoney(total).toDouble();
  }

  /// Cuánto falta por un partido concreto (contexto del cargo).
  ///
  /// [saldoAnteriorAlPartido]: saldo del jugador al registrar ese partido
  /// (snapshot en `saldos_historicos.saldo_anterior`).
  static double obtenerPendientePartido({
    required double saldoAnteriorAlPartido,
    required double cargoPartido,
    required double montoPagadoEnPartido,
  }) {
    return pendienteEnCobro(
      saldoAnterior: saldoAnteriorAlPartido,
      cargoPartido: cargoPartido,
      montoPagado: montoPagadoEnPartido,
    );
  }

  /// Si el cargo del partido quedó cubierto (neto, con crédito aplicado).
  static bool partidoEstaCerrado({
    required double saldoAnteriorAlPartido,
    required double cargoPartido,
    required double montoPagadoEnPartido,
  }) =>
      obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAnteriorAlPartido,
        cargoPartido: cargoPartido,
        montoPagadoEnPartido: montoPagadoEnPartido,
      ) <=
      0.005;

  /// Suma de deuda neta de todos los jugadores del grupo (un organizador).
  static double obtenerPendienteGrupo({
    required Iterable<double> saldosAcumulados,
  }) {
    var total = 0.0;
    for (final saldo in saldosAcumulados) {
      total += obtenerPendienteJugador(saldoAcumulado: saldo);
    }
    return roundMoney(total).toDouble();
  }

  /// Saldo anterior inmutable de un partido ya registrado.
  ///
  /// [snapshotHistorico]: valor de `saldos_historicos.saldo_anterior`.
  /// Si es null (partido antiguo sin historial), devuelve 0 — no recalcular en UI.
  static double saldoAnteriorAlPartido({required double? snapshotHistorico}) {
    if (snapshotHistorico == null) return 0;
    return roundMoney(snapshotHistorico).toDouble();
  }

  /// Clave `partidoId:jugadorId` para snapshots en lecturas batch.
  static String claveSnapshotPartidoJugador({
    required Object partidoId,
    required Object jugadorId,
  }) =>
      '$partidoId:$jugadorId';

  /// Pendiente neto de un detalle (lectura).
  ///
  /// Con [exigirSnapshot] (default), falta de snapshot → [DatosInconsistentesException].
  /// En listados de organizador (home/grupo/ficha) pasar `false` para no tumbar
  /// pantallas enteras cuando hay datos de prueba o legacy sin ledger.
  static double pendienteNetoDetalle({
    required int partidoId,
    required Object jugadorId,
    required double cargoPartido,
    required double montoPagadoEnPartido,
    required double? snapshotSaldoAnterior,
    bool exigirSnapshot = true,
  }) {
    if (snapshotSaldoAnterior == null && exigirSnapshot) {
      throw DatosInconsistentesException(
        'Datos inconsistentes: falta snapshot saldo_anterior '
        '(jugador $jugadorId, partido $partidoId)',
      );
    }
    return obtenerPendientePartido(
      saldoAnteriorAlPartido: saldoAnteriorAlPartido(
        snapshotHistorico: snapshotSaldoAnterior,
      ),
      cargoPartido: cargoPartido,
      montoPagadoEnPartido: montoPagadoEnPartido,
    );
  }

  /// Estado de cobro de un detalle_partido (lectura UI).
  ///
  /// Sin snapshot y [exigirSnapshot]=false (default): trata saldo_anterior=0
  /// para no tumbar pantallas con datos legacy/demo.
  static EstadoPagoDetalle estadoPagoDetalle({
    required int partidoId,
    required Object jugadorId,
    required double cargoPartido,
    required double montoPagadoEnPartido,
    required double? snapshotSaldoAnterior,
    bool exigirSnapshot = false,
  }) {
    if (snapshotSaldoAnterior == null && exigirSnapshot) {
      throw DatosInconsistentesException(
        'Datos inconsistentes: falta snapshot saldo_anterior '
        '(jugador $jugadorId, partido $partidoId)',
      );
    }
    final saldoAnt = saldoAnteriorAlPartido(
      snapshotHistorico: snapshotSaldoAnterior,
    );
    final pendiente = obtenerPendientePartido(
      saldoAnteriorAlPartido: saldoAnt,
      cargoPartido: cargoPartido,
      montoPagadoEnPartido: montoPagadoEnPartido,
    );
    return EstadoPagoDetalle(
      pendienteNeto: pendiente,
      partidoCerrado: partidoEstaCerrado(
        saldoAnteriorAlPartido: saldoAnt,
        cargoPartido: cargoPartido,
        montoPagadoEnPartido: montoPagadoEnPartido,
      ),
      saldoRestanteTrasPartido: saldoTrasMovimiento(
        saldoAnterior: saldoAnt,
        cargoPartido: cargoPartido,
        montoPagado: montoPagadoEnPartido,
      ),
      montoPagadoEnPartido: roundMoney(montoPagadoEnPartido).toDouble(),
    );
  }

  /// Suma pendiente neto de detalles asistidos (lectura batch).
  ///
  /// No exige snapshot: filas sin historial usan saldo_anterior 0 (legacy/demo)
  /// para no tumbar Inicio/Grupo del organizador.
  static Map<String, double> pendienteNetoPorJugadorBatch({
    required Iterable<String> jugadorIds,
    required List<dynamic> detalleRows,
    required Map<String, double> snapshotsPorPartidoJugador,
    required String Function(Map<String, dynamic> row) jugadorIdDeFila,
    required int Function(Map<String, dynamic> row) partidoIdDeFila,
  }) {
    final result = <String, double>{for (final id in jugadorIds) id: 0.0};

    for (final row in detalleRows) {
      final map = Map<String, dynamic>.from(row as Map);
      final jid = jugadorIdDeFila(map);
      if (!result.containsKey(jid)) continue;
      if (map['asistio'] == false || map['asistio'] == 0) continue;

      final pid = partidoIdDeFila(map);
      final key = claveSnapshotPartidoJugador(partidoId: pid, jugadorId: jid);
      final pend = pendienteNetoDetalle(
        partidoId: pid,
        jugadorId: jid,
        cargoPartido: (map['total'] as num).toDouble(),
        montoPagadoEnPartido: (map['monto_pagado'] as num?)?.toDouble() ?? 0,
        snapshotSaldoAnterior: snapshotsPorPartidoJugador[key],
        exigirSnapshot: false,
      );
      if (pend > 0.005) {
        result[jid] = roundMoney(result[jid]! + pend).toDouble();
      }
    }

    return result;
  }

  /// Saldo vivo para preview **antes** de guardar un partido (formulario).
  /// No usar en partidos ya registrados; ahí usar [saldoAnteriorAlPartido].
  static double saldoAnteriorPreview({
    required double saldoAcumuladoActual,
    double? snapshotAlEditar,
  }) =>
      snapshotAlEditar ?? saldoAcumuladoActual;

  /// Saldo tras aplicar solo un cargo (sin pago).
  static double saldoTrasCargo({
    required double saldoAcumulado,
    required double cargoPartido,
  }) =>
      saldoTrasMovimiento(
        saldoAnterior: saldoAcumulado,
        cargoPartido: cargoPartido,
        montoPagado: 0,
      );

  /// Saldo tras aplicar solo un pago (sin cargo).
  static double saldoTrasPago({
    required double saldoAcumulado,
    required double montoPagado,
  }) =>
      saldoTrasMovimiento(
        saldoAnterior: saldoAcumulado,
        cargoPartido: 0,
        montoPagado: montoPagado,
      );

  /// Saldo tras aplicar cargo y pago (escritura / preview).
  static double saldoTrasMovimiento({
    required double saldoAnterior,
    required double cargoPartido,
    required double montoPagado,
  }) =>
      CalculationService.saldoDespuesPago(
        saldoAnterior: saldoAnterior,
        cargoPartido: cargoPartido,
        montoPagado: montoPagado,
      );

  /// @deprecated Suma bruta (ignora crédito). Usar [obtenerPendienteJugador].
  @Deprecated('Usar obtenerPendienteJugador(saldoAcumulado: ...)')
  static double totalPendientePartidosImpagos({
    required Iterable<({double total, double montoPagado})> detallesImpagos,
  }) {
    var sum = 0.0;
    for (final d in detallesImpagos) {
      final p = roundMoney(d.total - d.montoPagado).toDouble();
      if (p > 0.005) sum += p;
    }
    return roundMoney(sum).toDouble();
  }

  static ComprobanteValidacionDecision evaluarValidacionComprobante({
    required bool aprobado,
    required bool pagado,
    required bool comprobanteValidado,
    required double pendientePartido,
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
    // No usar detalle.pagado: puede quedar true con deuda neta pendiente.
    if (pendientePartido <= 0.005) {
      return const ComprobanteValidacionDecision(
        accion: ComprobanteValidacionAccion.soloMarcarComprobante,
      );
    }
    final declarado = montoPagoDeclarado != null && montoPagoDeclarado > 0
        ? roundMoney(montoPagoDeclarado).toDouble()
        : pendientePartido;
    return ComprobanteValidacionDecision(
      accion: ComprobanteValidacionAccion.abonarPendiente,
      abono: declarado,
    );
  }

  static String conceptoValidacionOrganizador({required bool esAbono}) =>
      esAbono ? 'Abono validado por organizador' : 'Pago validado por organizador';
}
