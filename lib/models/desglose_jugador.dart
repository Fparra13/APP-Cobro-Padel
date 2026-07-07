import '../constants/conceptos_cobro.dart';
import '../domain/cobro_logic.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';
import 'costo_variable.dart';
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
  });

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
