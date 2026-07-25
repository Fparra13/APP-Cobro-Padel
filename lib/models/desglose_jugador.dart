import '../constants/conceptos_cobro.dart';
import '../domain/cobro_logic.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';
import 'costo_variable.dart';
import 'desglose_gasto_comprobante.dart';
import 'detalle_partido.dart';
import 'partido.dart';

class DesgloseJugador {
  final int jugadorId;
  final String? jugadorSupabaseId;
  final String nombre;
  final double saldoAnterior;
  final double cancha;
  final double pelotas;
  final Map<String, double> variables;
  final double totalPartido;
  final double totalDebido;
  final double montoPagado;
  final double saldoRestante;
  final bool pagado;
  /// Saldo vivo en la cuenta con el organizador del partido
  /// (`organizador_jugadores.saldo_acumulado`).
  final double? saldoAcumuladoCuenta;

  /// Path Storage del comprobante de cancha (opcional).
  final String? comprobanteCanchaUrl;

  /// Path Storage del comprobante de pelotas (opcional).
  final String? comprobantePelotasUrl;

  /// Variables enriquecidas (concepto/monto/comprobante) desde RPC.
  final List<DesgloseGastoComprobante> gastosVariables;

  const DesgloseJugador({
    this.jugadorId = 0,
    this.jugadorSupabaseId,
    required this.nombre,
    required this.saldoAnterior,
    required this.cancha,
    required this.pelotas,
    required this.variables,
    required this.totalPartido,
    required this.totalDebido,
    required this.montoPagado,
    required this.saldoRestante,
    required this.pagado,
    this.saldoAcumuladoCuenta,
    this.comprobanteCanchaUrl,
    this.comprobantePelotasUrl,
    this.gastosVariables = const [],
  });

  /// Parsea `variables` del RPC: array enriquecido o mapa legacy concepto→monto.
  static ({
    Map<String, double> amounts,
    List<DesgloseGastoComprobante> gastos,
  }) parseVariablesRpc(dynamic varsRaw) {
    final amounts = <String, double>{};
    final gastos = <DesgloseGastoComprobante>[];

    if (varsRaw is List) {
      for (final item in varsRaw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final concepto = (map['concepto'] as String?)?.trim();
        if (concepto == null || concepto.isEmpty) continue;
        final monto = _toDouble(map['monto']);
        final url = (map['comprobante_url'] as String?)?.trim();
        final normalizedUrl =
            (url != null && url.isNotEmpty) ? url : null;
        if (monto > 0) {
          amounts[concepto] = monto;
        }
        gastos.add(
          DesgloseGastoComprobante(
            concepto: concepto,
            monto: monto,
            comprobanteUrl: normalizedUrl,
          ),
        );
      }
      return (amounts: amounts, gastos: gastos);
    }

    if (varsRaw is Map) {
      for (final entry in varsRaw.entries) {
        final concepto = entry.key.toString().trim();
        if (concepto.isEmpty) continue;
        final monto = _toDouble(entry.value);
        if (monto > 0) {
          amounts[concepto] = monto;
          gastos.add(
            DesgloseGastoComprobante(concepto: concepto, monto: monto),
          );
        }
      }
    }

    return (amounts: amounts, gastos: gastos);
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// Ítems con path no vacío para la sección de comprobantes de gastos.
  List<({String label, String path})> comprobantesGastosItems({
    required String canchaLabel,
    required String pelotasLabel,
  }) {
    final items = <({String label, String path})>[];
    final canchaUrl = comprobanteCanchaUrl?.trim();
    if (canchaUrl != null && canchaUrl.isNotEmpty) {
      items.add((label: canchaLabel, path: canchaUrl));
    }
    final pelotasUrl = comprobantePelotasUrl?.trim();
    if (pelotasUrl != null && pelotasUrl.isNotEmpty) {
      items.add((label: pelotasLabel, path: pelotasUrl));
    }
    for (final g in gastosVariables) {
      if (!g.tieneComprobante) continue;
      items.add((label: g.concepto, path: g.comprobanteUrl!.trim()));
    }
    return items;
  }

  /// Crédito a favor en la cuenta del jugador (no solo en este partido).
  double get creditoCuenta {
    if (saldoAcumuladoCuenta == null) return 0;
    return CobroLogic.obtenerCreditoJugador(
      saldoAcumulado: saldoAcumuladoCuenta!,
    );
  }

  /// Deuda viva de la cuenta con este organizador (SSOT).
  double get pendienteCuenta {
    if (saldoAcumuladoCuenta == null) return 0;
    return CobroLogic.obtenerPendienteJugador(
      saldoAcumulado: saldoAcumuladoCuenta!,
    );
  }

  /// Pendiente a mostrar/cobrar en UI de organizador.
  /// Prefiere saldo de cuenta cuando está disponible.
  double get pendienteOrganizador {
    if (saldoAcumuladoCuenta != null) return pendienteCuenta;
    return pendientePartido;
  }

  /// True si el organizador aún debe cobrar a este jugador.
  bool get tieneCobroPendienteOrganizador => pendienteOrganizador > 0.005;

  /// Vista “pagado / al día” para el organizador (SSOT cuenta si existe).
  bool get alDiaOrganizador {
    if (saldoAcumuladoCuenta != null) return pendienteCuenta <= 0.005;
    return pagadoEnPartido;
  }

  bool get pagoParcial => !pagadoEnPartido && montoPagado > 0.005;

  String get jugadorKeyId =>
      jugadorSupabaseId ?? (jugadorId > 0 ? jugadorId.toString() : '');

  /// Alias para compatibilidad con reportes existentes.
  double get totalConDeuda => saldoRestante > 0 ? saldoRestante : 0;

  double get costoCanchaPelotas => cancha + pelotas;

  double get costoExtras =>
      variables.values.fold(0.0, (s, v) => s + v);

  double get saldoFavorAplicado => CalculationService.saldoFavorAplicado(
        saldoAnterior: saldoAnterior,
        cargoPartido: totalPartido,
      );

  double get totalATransferir =>
      saldoRestante > 0 ? saldoRestante : 0;

  bool get tieneSaldoAFavorAnterior => saldoAnterior < 0;

  bool get generaSaldoAFavor => saldoRestante < -0.005;

  /// Neto a pagar por este partido (sin deuda anterior positiva).
  double get netoAPagarPartido => CalculationService.netoAPagarPartido(
        saldoAnterior: saldoAnterior,
        cargoPartido: totalPartido,
      );

  /// Pendiente neto en el contexto del partido (incluye deuda anterior positiva).
  double get pendientePartido => CobroLogic.obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAnterior,
        cargoPartido: totalPartido,
        montoPagadoEnPartido: montoPagado,
      );

  /// Pendiente solo del cargo de este partido (sin deuda anterior acumulada).
  double get pendienteMarginalPartido => CalculationService.pendientePartido(
        saldoAnterior: saldoAnterior,
        cargoPartido: totalPartido,
        montoPagado: montoPagado,
      );

  bool get partidoCubiertoMarginal => CalculationService.partidoCubierto(
        saldoAnterior: saldoAnterior,
        cargoPartido: totalPartido,
        montoPagado: montoPagado,
      );

  double get saldoRestantePartido => CobroLogic.saldoTrasMovimiento(
        saldoAnterior: saldoAnterior,
        cargoPartido: totalPartido,
        montoPagado: montoPagado,
      );

  /// Partido cubierto según snapshot + pagos (no usa [pagado] almacenado).
  bool get pagadoEnPartido => CobroLogic.partidoEstaCerrado(
        saldoAnteriorAlPartido: saldoAnterior,
        cargoPartido: totalPartido,
        montoPagadoEnPartido: montoPagado,
      );

  bool get generaSaldoAFavorPartido =>
      pagadoEnPartido && saldoRestantePartido < -0.005;

  List<({String concepto, double monto})> get lineas {
    final items = <({String concepto, double monto})>[];
    if (cancha > 0) items.add((concepto: ConceptosCobro.cancha, monto: cancha));
    if (pelotas > 0) items.add((concepto: ConceptosCobro.pelotas, monto: pelotas));
    for (final e in variables.entries) {
      if (e.value > 0) items.add((concepto: e.key, monto: e.value));
    }
    return items;
  }
}

class DesglosePartido {
  static List<DesgloseJugador> calcular({
    required Partido partido,
    required List<DetallePartido> detalles,
    required List<CostoVariable> costosVariables,
    required Map<int, List<AsignacionCostoVariable>> asignacionesPorCosto,
    required Map<int, double> saldosAnteriores,
  }) {
    final asistentes =
        detalles.where((d) => d.asistio).map((d) => d.jugadorId).toList();
    final n = asistentes.length;
    if (n == 0) return [];

    final canchaU = CalculationService.prorrateoCancha(
      costoCancha: partido.costoCancha,
      cantidadAsistentes: n,
    );
    final pelotasU = CalculationService.prorrateoPelotas(
      costoPelotas: partido.costoPelotas,
      cantidadAsistentes: n,
    );

    final varsPorJugador = <int, Map<String, double>>{};
    for (final id in asistentes) {
      varsPorJugador[id] = {};
    }

    for (final cv in costosVariables) {
      final asignaciones = asignacionesPorCosto[cv.id] ?? [];
      for (final a in asignaciones) {
        if (asistentes.contains(a.jugadorId)) {
          varsPorJugador[a.jugadorId]![cv.concepto] =
              roundMoney(a.monto).toDouble();
        }
      }
    }

    return detalles.where((d) => d.asistio).map((d) {
      final saldoAnt =
          roundMoney(saldosAnteriores[d.jugadorId] ?? 0).toDouble();
      final vars = varsPorJugador[d.jugadorId] ?? {};
      final totalVars = vars.values.fold(0.0, (s, v) => s + v);
      final totalPartido = CalculationService.cargoPartido(
        prorrateoFijo: canchaU + pelotasU,
        totalVariables: totalVars,
      );
      final totalDebido = CalculationService.totalDebido(
        saldoAnterior: saldoAnt,
        cargoPartido: totalPartido,
      );
      final montoPagado = roundMoney(d.montoPagado).toDouble();
      final saldoRestante = CalculationService.saldoDespuesPago(
        saldoAnterior: saldoAnt,
        cargoPartido: totalPartido,
        montoPagado: montoPagado,
      );

      return DesgloseJugador(
        jugadorId: d.jugadorId,
        nombre: d.nombreJugador ?? '',
        saldoAnterior: saldoAnt,
        cancha: canchaU,
        pelotas: pelotasU,
        variables: vars,
        totalPartido: totalPartido,
        totalDebido: totalDebido,
        montoPagado: montoPagado,
        saldoRestante: saldoRestante,
        pagado: d.pagado,
      );
    }).toList();
  }
}
