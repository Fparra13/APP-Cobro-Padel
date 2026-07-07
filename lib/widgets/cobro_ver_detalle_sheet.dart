import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../domain/deuda_explicacion.dart';
import '../models/desglose_jugador.dart';
import '../models/saldo_historico.dart';
import '../models/detalle_partido.dart';
import '../domain/cobro_logic.dart';
import '../utils/cobro_jugador_ui.dart';
import '../utils/formatters.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/player_matches_to_close.dart';
import 'matchpay_ui.dart';
import 'sport_icon.dart';

/// Detalle de un partido pendiente — pago siempre vía cuenta global.
class CobroVerDetalleSheet extends StatelessWidget {
  final DetallePartido detalle;
  final DesgloseJugador? desglose;
  final VoidCallback? onPayTotal;
  final VoidCallback? onPayAbono;

  final double? saldoAnteriorAlPartido;
  final double? saldoAcumuladoJugador;
  final bool esAnclaCuenta;
  final List<SaldoHistorico>? historialSaldo;

  const CobroVerDetalleSheet({
    super.key,
    required this.detalle,
    this.desglose,
    this.saldoAnteriorAlPartido,
    this.saldoAcumuladoJugador,
    this.esAnclaCuenta = false,
    this.historialSaldo,
    this.onPayTotal,
    this.onPayAbono,
  });

  static Future<void> show(
    BuildContext context, {
    required DetallePartido detalle,
    DesgloseJugador? desglose,
    double? saldoAnteriorAlPartido,
    double? saldoAcumuladoJugador,
    bool esAnclaCuenta = false,
    List<SaldoHistorico>? historialSaldo,
    VoidCallback? onPayTotal,
    VoidCallback? onPayAbono,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MatchPayTokens.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: CobroVerDetalleSheet(
            detalle: detalle,
            desglose: desglose,
            saldoAnteriorAlPartido: saldoAnteriorAlPartido,
            saldoAcumuladoJugador: saldoAcumuladoJugador,
            esAnclaCuenta: esAnclaCuenta,
            historialSaldo: historialSaldo,
            onPayTotal: onPayTotal,
            onPayAbono: onPayAbono,
          ),
        ),
      ),
    );
  }

  String _titulo(MatchPayStrings l10n) => tituloDetallePartido(detalle, l10n);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snap = saldoAnteriorAlPartido ?? desglose?.saldoAnterior;
    final marginal = montoMarginalPartidoCobro(
      detalle,
      desglose,
      saldoAnteriorPartido: snap,
    );
    final pendiente = esAnclaCuenta && saldoAcumuladoJugador != null
        ? CobroLogic.obtenerPendienteJugador(
            saldoAcumulado: saldoAcumuladoJugador!,
          )
        : marginal;
    final explicacionCuenta = esAnclaCuenta &&
            saldoAcumuladoJugador != null &&
            historialSaldo != null
        ? explicarDeudaJugador(
            saldoAcumulado: saldoAcumuladoJugador!,
            historial: historialSaldo!,
          )
        : null;
    final antiguedad = antiguedadPartidoTexto(detalle.fechaPartido);
    final urgente = partidoRequiereAtencionUrgente(detalle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MatchPayTokens.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (detalle.sportType != null)
              SportEmoji(sport: detalle.sportType, size: 28)
            else
              Icon(Icons.sports, color: MatchPayTokens.inkMuted, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.tr('cobrosViewChargeTitle'),
                style: MatchPayTokens.titleMediumStyle(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _titulo(l10n),
          style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 17),
        ),
        if (antiguedad.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            urgente
                ? l10n.tr('cobrosAgeUrgent', params: {'when': antiguedad})
                : antiguedad,
            style: MatchPayTokens.bodySmallStyle(
              color: urgente
                  ? MatchPayTokens.accentUrgent
                  : MatchPayTokens.inkMuted,
            ),
          ),
        ],
        const SizedBox(height: 16),
        MatchPaySurfaceCard(
          child: esAnclaCuenta && explicacionCuenta != null
              ? DeudaExplicacionLineas(explicacion: explicacionCuenta)
              : desglose != null
                  ? DesgloseCalculoPanel(
                      desglose: desglose!,
                      soloPartidoActual: true,
                      showLineasPartido: true,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.tr('breakdownMatchAmount'),
                          style: MatchPayTokens.bodySmallStyle(),
                        ),
                        Text(
                          formatMoney(detalle.total),
                          style: MatchPayTokens.titleSmallStyle(),
                        ),
                        if (!esAnclaCuenta &&
                            pendiente > 0.005 &&
                            detalle.montoPagado > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.tr(
                              'cobrosPartialPaid',
                              params: {
                                'paid': formatMoney(detalle.montoPagado),
                                'pending': formatMoney(pendiente),
                              },
                            ),
                            style: MatchPayTokens.bodySmallStyle(),
                          ),
                        ],
                      ],
                    ),
        ),
        if (!esAnclaCuenta) ...[
          const SizedBox(height: 8),
          Text(
            estadoTextoCobro(
              detalle,
              l10n,
              saldoAnteriorAlPartido: snap,
            ),
            style: MatchPayTokens.bodySmallStyle(
              color: detalle.comprobantePendienteValidacion
                  ? MatchPayTokens.accentUrgent
                  : MatchPayTokens.inkMuted,
            ),
          ),
        ],
        if ((onPayTotal != null || onPayAbono != null) &&
            !detalle.comprobantePendienteValidacion &&
            pendiente > 0.005) ...[
          const SizedBox(height: 16),
          if (!esAnclaCuenta) ...[
            Text(
              l10n.tr(
                'cobrosMatchPending',
                params: {'amount': formatMoney(pendiente)},
              ),
              style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
          ],
          if (onPayTotal != null)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  onPayTotal!();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: MatchPayTokens.accentUrgent,
                ),
                child: Text(l10n.tr('cobrosPayTotalBtn')),
              ),
            ),
          if (onPayAbono != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  onPayAbono!();
                },
                child: Text(l10n.tr('cobrosAbonoShort')),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.tr('cobrosAutoApplyHint'),
            style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
