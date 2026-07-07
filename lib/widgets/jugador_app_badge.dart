import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/jugador.dart';

/// Indicador 📱 app instalada / 👤 sin app.
class JugadorAppBadge extends StatelessWidget {
  final Jugador jugador;
  final bool compact;

  const JugadorAppBadge({
    super.key,
    required this.jugador,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conApp = jugador.tieneMatchPayApp;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: conApp
            ? MatchPayTokens.accentCreditBg
            : MatchPayTokens.accentUrgentBg.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            conApp ? '📱' : '👤',
            style: TextStyle(fontSize: compact ? 11 : 12),
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              conApp ? l10n.tr('playerHasApp') : l10n.tr('playerNoApp'),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: conApp
                    ? MatchPayTokens.accentCredit
                    : MatchPayTokens.accentUrgent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
