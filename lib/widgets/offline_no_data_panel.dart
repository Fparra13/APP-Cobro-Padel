import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Estado vacío cuando no hay snapshot offline para esta pantalla.
class OfflineNoDataPanel extends StatelessWidget {
  const OfflineNoDataPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: MatchPayTokens.inkMuted,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.tr('offlineNoDataAvailable'),
              textAlign: TextAlign.center,
              style: MatchPayTokens.titleSmallStyle(),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tr('offlineNoDataAvailableHint'),
              textAlign: TextAlign.center,
              style: MatchPayTokens.bodySmallStyle(),
            ),
          ],
        ),
      ),
    );
  }
}
