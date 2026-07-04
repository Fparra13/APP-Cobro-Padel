import 'package:flutter/material.dart';

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
    final Color estadoColor;
    final String estadoLabel;
    if (detalle.pagado) {
      estadoColor = const Color(0xFF059669);
      estadoLabel = l10n.tr('playerMatchPaid');
    } else if (enRevision) {
      estadoColor = const Color(0xFFD97706);
      estadoLabel = l10n.tr('cobroStatusReceiptReview');
    } else if (pendiente) {
      estadoColor = const Color(0xFFEA580C);
      estadoLabel = l10n.tr('pendingStatus');
    } else {
      estadoColor = Colors.grey.shade600;
      estadoLabel = l10n.tr('playerMatchPlayed');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: detalle.sportType != null
                ? SportEmoji(sport: detalle.sportType, size: 22)
                : Icon(Icons.event_rounded, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Color(0xFF111827),
                  ),
                ),
                if (subtitulo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  estadoLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: estadoColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(detalle.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: Color(0xFF111827),
                ),
              ),
              if (detalle.montoPagado > 0.005 && !detalle.pagado)
                Text(
                  l10n.tr(
                    'playerMatchPaidAmount',
                    params: {'amount': formatMoney(detalle.montoPagado)},
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
