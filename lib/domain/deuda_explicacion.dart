import '../domain/cobro_logic.dart';
import '../models/saldo_historico.dart';
import '../utils/formatters.dart';

/// Una línea del desglose simple de cuenta.
class LineaExplicacionDeuda {
  final String labelKey;
  final double monto;
  final bool esResta;

  const LineaExplicacionDeuda({
    required this.labelKey,
    required this.monto,
    this.esResta = false,
  });
}

/// Explicación legible de la deuda actual (SSOT: saldo_acumulado).
class ExplicacionDeudaJugador {
  final double deudaActual;
  final List<LineaExplicacionDeuda> lineas;
  final int? partidoIdContexto;
  final String? subtituloKey;
  final Map<String, String> subtituloParams;

  const ExplicacionDeudaJugador({
    required this.deudaActual,
    required this.lineas,
    this.partidoIdContexto,
    this.subtituloKey,
    this.subtituloParams = const {},
  });
}

/// Crédito a favor en cuenta (saldo_acumulado negativo).
double saldoAFavorJugador(double saldoAcumulado) =>
    CobroLogic.obtenerCreditoJugador(saldoAcumulado: saldoAcumulado);

/// Construye el desglose a partir del historial de saldos.
///
/// Formato: monto del partido → deuda anterior o saldo a favor → (opcional
/// pagos) → deuda actual en pantalla.
ExplicacionDeudaJugador? explicarDeudaJugador({
  required double saldoAcumulado,
  required List<SaldoHistorico> historial,
}) {
  final deudaActual =
      CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoAcumulado);
  if (deudaActual <= 0.005) return null;

  final cargosPartido = historial
      .where((h) => h.cargoPartido > 0.005 && h.partidoId != null)
      .toList()
    ..sort((a, b) {
      final cmp = a.fecha.compareTo(b.fecha);
      if (cmp != 0) return cmp;
      return (a.partidoId ?? 0).compareTo(b.partidoId ?? 0);
    });

  final ultimoCargoPartido =
      cargosPartido.isNotEmpty ? cargosPartido.last : null;

  if (ultimoCargoPartido == null) {
    return ExplicacionDeudaJugador(
      deudaActual: deudaActual,
      lineas: [
        LineaExplicacionDeuda(
          labelKey: 'deudaSimpleYouOweOnly',
          monto: deudaActual,
        ),
      ],
      subtituloKey: 'deudaExplainSubtitleAccumulated',
      subtituloParams: {'amount': formatMoney(deudaActual)},
    );
  }

  final h = ultimoCargoPartido;
  final lineas = <LineaExplicacionDeuda>[
    LineaExplicacionDeuda(
      labelKey: 'deudaSimpleMatchAmount',
      monto: h.cargoPartido,
    ),
  ];

  if (h.saldoAnterior < -0.005) {
    lineas.add(
      LineaExplicacionDeuda(
        labelKey: 'deudaSimpleCredit',
        monto: -h.saldoAnterior,
        esResta: true,
      ),
    );
  } else if (h.saldoAnterior > 0.005) {
    lineas.add(
      LineaExplicacionDeuda(
        labelKey: 'deudaSimplePreviousDebt',
        monto: h.saldoAnterior,
      ),
    );
  }

  if (h.abono > 0.005) {
    lineas.add(
      LineaExplicacionDeuda(
        labelKey: 'deudaSimplePaidOnRegister',
        monto: h.abono,
        esResta: true,
      ),
    );
  }

  final saldoTrasCargo = roundMoney(h.saldoNuevo).toDouble();
  if ((saldoTrasCargo - deudaActual).abs() > 0.005 &&
      saldoTrasCargo > deudaActual) {
    lineas.add(
      LineaExplicacionDeuda(
        labelKey: 'deudaSimplePaymentsAfter',
        monto: roundMoney(saldoTrasCargo - deudaActual).toDouble(),
        esResta: true,
      ),
    );
  }

  String? subtituloKey;
  final subtituloParams = <String, String>{
    'amount': formatMoney(deudaActual),
  };

  if (h.saldoAnterior < -0.005) {
    subtituloKey = 'deudaExplainSubtitleCredit';
    subtituloParams['credit'] = formatMoney(-h.saldoAnterior);
    subtituloParams['charge'] = formatMoney(h.cargoPartido);
  } else if (h.saldoAnterior > 0.005) {
    subtituloKey = 'deudaExplainSubtitleCarried';
    subtituloParams['carried'] = formatMoney(h.saldoAnterior);
    subtituloParams['charge'] = formatMoney(h.cargoPartido);
  } else {
    subtituloKey = 'deudaExplainSubtitleSimple';
    subtituloParams['charge'] = formatMoney(h.cargoPartido);
  }

  return ExplicacionDeudaJugador(
    deudaActual: deudaActual,
    lineas: lineas,
    partidoIdContexto: h.partidoId,
    subtituloKey: subtituloKey,
    subtituloParams: subtituloParams,
  );
}

/// Abono anotado al registrar cada partido (fila de cargo en historial).
Map<int, double> abonoAlRegistrarPorPartido(List<SaldoHistorico> historial) {
  final map = <int, double>{};
  final cargos = historial
      .where((h) => h.partidoId != null && h.cargoPartido > 0.005)
      .toList()
    ..sort((a, b) {
      final cmp = a.fecha.compareTo(b.fecha);
      if (cmp != 0) return cmp;
      return (a.partidoId ?? 0).compareTo(b.partidoId ?? 0);
    });
  for (final h in cargos) {
    map.putIfAbsent(h.partidoId!, () => h.abono);
  }
  return map;
}

bool explicacionCuadraConSaldo({
  required ExplicacionDeudaJugador explicacion,
  required double saldoAcumulado,
}) {
  final esperado =
      CobroLogic.obtenerPendienteJugador(saldoAcumulado: saldoAcumulado);
  return (explicacion.deudaActual - esperado).abs() <= 0.005;
}
