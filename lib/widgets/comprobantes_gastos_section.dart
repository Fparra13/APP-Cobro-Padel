import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import 'comprobante_pago_tile.dart';

/// Sección read-only de comprobantes de gastos (organizador y jugador).
class ComprobantesGastosSection extends StatelessWidget {
  final List<({String label, String path})> items;
  final Widget? header;

  const ComprobantesGastosSection({
    super.key,
    required this.items,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.tr('expenseReceiptsTitle'),
                  style: MatchPayTokens.sectionLabelStyle(),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.tr('expenseReceiptsSubtitle'),
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.inkMuted,
                  ),
                ),
              ],
            ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ComprobantePagoTile(
                    comprobantePath: item.path,
                    onChanged: (_) {},
                    compact: true,
                    readOnly: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
