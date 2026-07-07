import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../domain/deuda_explicacion.dart';
import '../models/detalle_partido.dart';
import '../models/saldo_historico.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../widgets/desglose_cobro_panel.dart';
import '../widgets/matchpay_ui.dart';
import 'sport_icon.dart';

/// Cómo mostrar cada fila del historial de partidos del jugador.
enum PlayerMatchHistorialModo {
  /// Deuda en cuenta: solo el cargo del jugador en cada partido.
  cuentaConDeuda,
  /// Sin deuda consolidada: badge pagado/pendiente por partido.
  porPartido,
}

/// Fila de partido jugado (vista jugador, no ficha de admin).
class PlayerMatchHistoryTile extends StatelessWidget {
  final DetallePartido detalle;
  final double? saldoAnteriorAlPartido;
  final PlayerMatchHistorialModo modo;
  /// Abono al registrar el partido (historial de cargo). Solo en [cuentaConDeuda].
  final double? abonoAlRegistrar;

  const PlayerMatchHistoryTile({
    super.key,
    required this.detalle,
    this.saldoAnteriorAlPartido,
    this.modo = PlayerMatchHistorialModo.porPartido,
    this.abonoAlRegistrar,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fecha = detalle.fechaPartido;
    final recinto = detalle.recintoPartido?.trim();
    final sportPalette = detalle.sportType != null
        ? SportThemeConfig.paletteFor(detalle.sportType!)
        : null;
    final titulo = fecha != null
        ? formatDiaCompleto(fecha)
        : l10n.tr('matchNumber', params: {'id': '${detalle.partidoId}'});
    final subtitulo = [
      if (detalle.sportType != null)
        detalle.sportType!.labelForLocale(
          context.readSettings().locale.languageCode,
        ),
      if (recinto != null && recinto.isNotEmpty) recinto,
    ].join(' · ');

    final snap = saldoAnteriorAlPartido;
    final enRevision = detalle.comprobantePendienteValidacion;
    final cuentaConDeuda = modo == PlayerMatchHistorialModo.cuentaConDeuda;
    final montoAbonadoAlRegistrar = cuentaConDeuda
        ? (abonoAlRegistrar ?? 0)
        : detalle.montoPagado;

    Color? estadoColor;
    String? estadoLabel;
    var mostrarDeclaradoPendiente = false;
    if (!cuentaConDeuda) {
      final marginal = montoMarginalPartidoCobro(
        detalle,
        null,
        saldoAnteriorPartido: snap,
      );
      final partidoCerrado = marginal <= 0.005;
      if (partidoCerrado && !enRevision) {
        estadoColor = MatchPayTokens.accentSuccess;
        estadoLabel = l10n.tr('playerMatchPaid');
      } else if (enRevision) {
        estadoColor = const Color(0xFFD97706);
        estadoLabel = l10n.tr('cobroStatusReceiptReview');
      } else if (marginal > 0.005) {
        estadoColor = MatchPayTokens.accentUrgent;
        estadoLabel = l10n.tr('pendingStatus');
        mostrarDeclaradoPendiente = true;
      } else {
        estadoColor = MatchPayTokens.accentSuccess;
        estadoLabel = l10n.tr('playerMatchPaid');
      }
    } else if (enRevision) {
      estadoColor = const Color(0xFFD97706);
      estadoLabel = l10n.tr('cobroStatusReceiptReview');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (sportPalette?.primary ?? MatchPayTokens.inkMuted)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: detalle.sportType != null
                ? SportEmoji(sport: detalle.sportType, size: 22)
                : Icon(Icons.event_rounded, color: MatchPayTokens.inkMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MatchPayTokens.titleSmallStyle().copyWith(
                    fontSize: 13.5,
                  ),
                ),
                if (subtitulo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 12,
                    ),
                  ),
                ],
                if (cuentaConDeuda && montoAbonadoAlRegistrar > 0.005) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.tr(
                      'playerMatchPaidOnRegister',
                      params: {'amount': formatMoney(montoAbonadoAlRegistrar)},
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11.5,
                      color: MatchPayTokens.inkMuted,
                    ),
                  ),
                ] else if (!cuentaConDeuda &&
                    mostrarDeclaradoPendiente &&
                    (detalle.montoPagoDeclarado ?? 0) > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.tr(
                      'playerMatchPaidAmount',
                      params: {
                        'amount':
                            formatMoney(detalle.montoPagoDeclarado ?? 0),
                      },
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 11.5,
                      color: MatchPayTokens.accentUrgent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, maxWidth: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatMoney(detalle.total),
                    maxLines: 1,
                    style: MatchPayTokens.statValueStyle().copyWith(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                if (cuentaConDeuda)
                  Text(
                    l10n.tr('playerMatchYourShare'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MatchPayTokens.bodySmallStyle().copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (estadoLabel != null && estadoColor != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: estadoColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      estadoLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MatchPayTokens.sectionLabelStyle(
                        color: estadoColor,
                      ).copyWith(
                        letterSpacing: 0,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista de partidos jugados (home, mis cobros, historial).
class PlayerMatchHistoryList extends StatelessWidget {
  final List<DetallePartido> partidos;
  final Map<int, double> saldosPorPartido;
  final PlayerMatchHistorialModo modo;
  final List<SaldoHistorico>? historialSaldo;

  const PlayerMatchHistoryList({
    super.key,
    required this.partidos,
    required this.saldosPorPartido,
    this.modo = PlayerMatchHistorialModo.porPartido,
    this.historialSaldo,
  });

  @override
  Widget build(BuildContext context) {
    final abonosAlRegistrar = modo == PlayerMatchHistorialModo.cuentaConDeuda &&
            historialSaldo != null
        ? abonoAlRegistrarPorPartido(historialSaldo!)
        : const <int, double>{};

    return MatchPaySurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < partidos.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: MatchPayTokens.borderSubtle,
              ),
            PlayerMatchHistoryTile(
              detalle: partidos[i],
              saldoAnteriorAlPartido: saldosPorPartido[partidos[i].partidoId],
              modo: modo,
              abonoAlRegistrar: abonosAlRegistrar[partidos[i].partidoId],
            ),
          ],
        ],
      ),
    );
  }
}
