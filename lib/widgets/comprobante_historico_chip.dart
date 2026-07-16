import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/comprobante_estado.dart';
import '../models/detalle_partido.dart';
import '../services/comprobante_service.dart';

/// Etiqueta histórica (no pendiente) + “Ver” para comprobante retenido.
class ComprobanteHistoricoChip extends StatelessWidget {
  final DetallePartido detalle;

  const ComprobanteHistoricoChip({super.key, required this.detalle});

  @override
  Widget build(BuildContext context) {
    if (!detalle.comprobanteEsHistorico) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final estado = detalle.comprobanteEstadoEfectivo;
    final label = estado == ComprobanteEstado.rechazado
        ? l10n.tr('cobroStatusReceiptRejected')
        : l10n.tr('cobroStatusReceiptSent');
    final color = MatchPayTokens.inkMuted;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: MatchPayTokens.bodySmallStyle(color: color).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (detalle.tieneComprobanteArchivo)
            TextButton(
              onPressed: () => showComprobanteViewer(
                context,
                relativePath: detalle.comprobanteUrl!,
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.tr('viewBtn'),
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
        ],
      ),
    );
  }
}
