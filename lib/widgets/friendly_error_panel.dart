import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Estado de error legible (sin detalles técnicos).
class FriendlyErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const FriendlyErrorPanel({
    super.key,
    required this.message,
    this.onRetry,
  });

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
              message,
              textAlign: TextAlign.center,
              style: MatchPayTokens.titleSmallStyle(),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.tr('retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
