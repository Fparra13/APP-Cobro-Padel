import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../models/detalle_partido.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'sport_icon.dart';

/// Fila de partido jugado (vista jugador, no ficha de admin).
class PlayerMatchHistoryTile extends StatelessWidget {
  final DetallePartido detalle;

  const PlayerMatchHistoryTile({super.key, required this.detalle});

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

    final pendiente = detalle.tieneDeudaEnCobro;
    final enRevision = detalle.comprobantePendienteValidacion;
    final montoDeclarado = detalle.montoPagoDeclarado ?? 0;
    final Color estadoColor;
    final String estadoLabel;
    if (detalle.pagado) {
      estadoColor = MatchPayTokens.accentSuccess;
      estadoLabel = l10n.tr('playerMatchPaid');
    } else if (enRevision) {
      estadoColor = const Color(0xFFD97706);
      estadoLabel = l10n.tr('cobroStatusReceiptReview');
    } else if (pendiente) {
      estadoColor = MatchPayTokens.accentUrgent;
      estadoLabel = l10n.tr('pendingStatus');
    } else {
      estadoColor = MatchPayTokens.inkMuted;
      estadoLabel = l10n.tr('playerMatchPlayed');
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
                if (montoDeclarado > 0 && !detalle.pagado) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.tr(
                      'playerMatchPaidAmount',
                      params: {
                        'amount': formatMoney(montoDeclarado),
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
