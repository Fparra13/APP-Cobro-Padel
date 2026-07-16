import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../services/calculation_service.dart';
import '../domain/cobro_logic.dart';
import '../l10n/matchpay_strings.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../utils/formatters.dart';
import 'matchpay_ui.dart';
import 'sport_icon.dart';

/// Filas del cálculo: partido + deuda anterior − saldo a favor − abonado = a transferir.
class DesgloseCalculoPanel extends StatelessWidget {
  final DesgloseJugador desglose;
  final bool compact;
  final bool showLineasPartido;
  /// Si true, solo muestra cargo del partido (sin deuda anterior acumulada).
  final bool soloPartidoActual;
  /// Monto a transferir a nivel cuenta (SSOT); anula el cálculo por partido.
  final double? montoTransferirCuenta;

  const DesgloseCalculoPanel({
    super.key,
    required this.desglose,
    this.compact = false,
    this.showLineasPartido = true,
    this.soloPartidoActual = false,
    this.montoTransferirCuenta,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = desglose;
    final deudaAnt =
        !soloPartidoActual && d.saldoAnterior > 0 ? d.saldoAnterior : 0.0;
    final saldoFavor = d.saldoAnterior < 0 ? -d.saldoAnterior : 0.0;
    final totalDebido =
        soloPartidoActual ? d.netoAPagarPartido : d.totalDebido;
    final usandoCuenta = !soloPartidoActual && montoTransferirCuenta != null;
    final aTransferir = soloPartidoActual
        ? d.pendienteMarginalPartido
        : (usandoCuenta
            ? (montoTransferirCuenta! > 0.005 ? montoTransferirCuenta! : 0.0)
            : (d.saldoRestante > 0 ? d.saldoRestante : 0.0));
    final saldoRestante = soloPartidoActual
        ? d.saldoRestantePartido
        : d.saldoRestante;
    final creditoCuentaVivo =
        usandoCuenta && aTransferir <= 0.005 ? d.creditoCuenta : 0.0;
    final pagado = soloPartidoActual
        ? d.partidoCubiertoMarginal
        : (usandoCuenta
            ? aTransferir <= 0.005
            : d.saldoRestante <= 0.005);
    final generaFavor = soloPartidoActual
        ? d.generaSaldoAFavorPartido
        : (usandoCuenta
            ? creditoCuentaVivo > 0.005
            : d.generaSaldoAFavor);
    final montoResultado = generaFavor
        ? (usandoCuenta ? creditoCuentaVivo : -saldoRestante)
        : aTransferir;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLineasPartido) ...[
          ...d.lineas.map(
            (l) => _Fila(
              label: l10n.translateConcept(l.concepto),
              monto: l.monto,
              compact: compact,
            ),
          ),
          if (d.lineas.isNotEmpty) const SizedBox(height: 4),
        ],
        _Fila(
          label: l10n.tr('breakdownMatchAmount'),
          monto: d.totalPartido,
          bold: true,
          compact: compact,
        ),
        if (deudaAnt > 0)
          _Fila(
            label: l10n.tr('breakdownPreviousDebt'),
            monto: deudaAnt,
            compact: compact,
            color: Colors.red.shade700,
          ),
        if (saldoFavor > 0)
          _Fila(
            label: l10n.tr('breakdownCreditBalance'),
            monto: saldoFavor,
            compact: compact,
            esResta: true,
            color: Colors.blue.shade700,
          ),
        Divider(height: compact ? 12 : 16),
        _Fila(
          label: l10n.tr('breakdownTotalDue'),
          monto: totalDebido,
          bold: true,
          compact: compact,
        ),
        if (d.montoPagado > 0)
          _Fila(
            label: l10n.tr('breakdownPaidAmount'),
            monto: d.montoPagado,
            compact: compact,
            esResta: true,
            color: Colors.green.shade700,
          ),
        Divider(height: compact ? 12 : 16),
        _Fila(
          label: pagado && generaFavor
              ? l10n.tr('breakdownCreditResult')
              : l10n.tr('breakdownToTransfer'),
          monto: montoResultado,
          bold: true,
          destacado: true,
          compact: compact,
          color: pagado
              ? Colors.green.shade800
              : (aTransferir > 0 ? Colors.orange.shade900 : Colors.green.shade800),
        ),
      ],
    );
  }
}

class CobroPartidoCard extends StatelessWidget {
  final DetallePartido detalle;
  final DesgloseJugador? desglose;
  final String? estadoExtra;
  final Widget? actions;
  final bool compact;
  final bool showLineasPartido;
  final bool soloPartidoActual;
  final double? montoTransferirCuenta;

  const CobroPartidoCard({
    super.key,
    required this.detalle,
    this.desglose,
    this.estadoExtra,
    this.actions,
    this.compact = false,
    this.showLineasPartido = true,
    this.soloPartidoActual = false,
    this.montoTransferirCuenta,
  });

  String _titulo(BuildContext context) {
    if (detalle.fechaPartido != null) {
      final recinto = detalle.recintoPartido?.trim();
      if (recinto != null && recinto.isNotEmpty) {
        return '${formatDiaCompleto(detalle.fechaPartido!)} · $recinto';
      }
      return formatDiaCompleto(detalle.fechaPartido!);
    }
    return context.tr('matchNumber', params: {'id': '${detalle.partidoId}'});
  }

  @override
  Widget build(BuildContext context) {
    final pendingApproval = detalle.comprobantePendienteValidacion;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 10),
      child: MatchPaySurfaceCard(
        padding: EdgeInsets.all(compact ? 12 : 14),
        urgent: pendingApproval,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detalle.sportType != null) ...[
              SportChargeChip(sport: detalle.sportType!),
              const SizedBox(height: 6),
            ],
            Text(
              _titulo(context),
              style: MatchPayTokens.titleSmallStyle().copyWith(
                fontSize: compact ? 14 : 16,
              ),
            ),
            const SizedBox(height: 8),
            if (desglose != null)
              DesgloseCalculoPanel(
                desglose: desglose!,
                compact: compact,
                showLineasPartido: showLineasPartido && !compact,
                soloPartidoActual: soloPartidoActual,
                montoTransferirCuenta: montoTransferirCuenta,
              )
            else
              _Fila(
                label: context.tr('breakdownMatchAmount'),
                monto: detalle.total,
                bold: true,
                compact: compact,
              ),
            if (estadoExtra != null) ...[
              const SizedBox(height: 8),
              Text(
                estadoExtra!,
                style: MatchPayTokens.bodySmallStyle(
                  color: pendingApproval
                      ? MatchPayTokens.accentUrgent
                      : MatchPayTokens.inkMuted,
                ).copyWith(fontSize: 12),
              ),
            ],
            if (actions != null) ...[
              const SizedBox(height: 12),
              actions!,
            ],
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final double monto;
  final bool bold;
  final bool destacado;
  final bool compact;
  final bool esResta;
  final Color? color;

  const _Fila({
    required this.label,
    required this.monto,
    this.bold = false,
    this.destacado = false,
    this.compact = false,
    this.esResta = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final montoTxt = esResta && !destacado
        ? '−${formatMoney(monto)}'
        : (destacado && monto < 0
            ? formatMoney(-monto)
            : formatMoney(monto));

    final style = TextStyle(
      fontSize: compact ? 12 : 13,
      fontWeight: bold || destacado ? FontWeight.w700 : FontWeight.normal,
      color: color ??
          (destacado
              ? Colors.orange.shade900
              : Colors.grey.shade800),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(montoTxt, style: style),
        ],
      ),
    );
  }
}

/// Título legible para un detalle de partido.
String tituloDetallePartido(DetallePartido d, MatchPayStrings l10n) {
  if (d.fechaPartido != null) {
    final recinto = d.recintoPartido?.trim();
    if (recinto != null && recinto.isNotEmpty) {
      return '${formatDiaCompleto(d.fechaPartido!)} · $recinto';
    }
    return formatDiaCompleto(d.fechaPartido!);
  }
  return l10n.tr('matchNumber', params: {'id': '${d.partidoId}'});
}

double montoMarginalPartidoCobro(
  DetallePartido d,
  DesgloseJugador? desglose, {
  double? saldoAnteriorPartido,
}) {
  if (desglose != null) return desglose.pendienteMarginalPartido;
  final saldo = saldoAnteriorPartido ?? 0;
  return CalculationService.pendientePartido(
    saldoAnterior: saldo,
    cargoPartido: d.total,
    montoPagado: d.montoPagado,
  );
}

double montoATransferirCobro(
  DetallePartido d,
  DesgloseJugador? desglose, {
  double? saldoAnteriorPartido,
}) {
  if (desglose != null) {
    return CobroLogic.obtenerPendientePartido(
      saldoAnteriorAlPartido: desglose.saldoAnterior,
      cargoPartido: desglose.totalPartido,
      montoPagadoEnPartido: desglose.montoPagado,
    );
  }
  if (saldoAnteriorPartido != null) {
    return CobroLogic.obtenerPendientePartido(
      saldoAnteriorAlPartido: saldoAnteriorPartido,
      cargoPartido: d.total,
      montoPagadoEnPartido: d.montoPagado,
    );
  }
  // Sin saldo anterior conocido: no calcular bruto aquí; el caller debe
  // proveer saldoAnteriorPartido o desglose.
  return CobroLogic.obtenerPendientePartido(
    saldoAnteriorAlPartido: 0,
    cargoPartido: d.total,
    montoPagadoEnPartido: d.montoPagado,
  );
}

String estadoTextoCobro(
  DetallePartido d,
  MatchPayStrings l10n, {
  double? saldoAnteriorAlPartido,
}) {
  if (d.comprobantePendienteValidacion) {
    final monto = d.montoPagoDeclarado;
    if (monto != null && monto > 0) {
      final tipo = d.pagoEsAbono == true
          ? l10n.tr('cobroReceiptTypePartial')
          : l10n.tr('cobroReceiptTypePayment');
      return l10n.tr(
        'cobroStatusReceiptReviewAmount',
        params: {'type': tipo, 'amount': formatMoney(monto)},
      );
    }
    return l10n.tr('cobroStatusReceiptReview');
  }
  // Alinear con el desglose del encuentro (solo cargo de ESTE partido),
  // no con deuda de cuenta/FIFO antiguo — si no, "A transferir $0" y
  // "Pendiente de pago" contradicen.
  final pendienteMatch = saldoAnteriorAlPartido != null
      ? CobroLogic.pendienteFifoDetalle(
          saldoAnterior: saldoAnteriorAlPartido,
          cargoPartido: d.total,
          montoPagadoEnPartido: d.montoPagado,
        )
      : CalculationService.pendientePartido(
          saldoAnterior: 0,
          cargoPartido: d.total,
          montoPagado: d.montoPagado,
        );
  if (pendienteMatch > 0.005) {
    if (d.montoPagado > 0.005) {
      return l10n.tr('cobroStatusPartialRegistered');
    }
    return l10n.tr('cobroStatusPending');
  }
  return l10n.tr('cobroStatusPaid');
}

List<DetallePartido> ordenarDeudasPorFecha(List<DetallePartido> deudas) {
  final copy = List<DetallePartido>.from(deudas);
  copy.sort((a, b) {
    final fa = a.fechaPartido ?? DateTime.fromMillisecondsSinceEpoch(0);
    final fb = b.fechaPartido ?? DateTime.fromMillisecondsSinceEpoch(0);
    return fb.compareTo(fa);
  });
  return copy;
}
