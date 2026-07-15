import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Estado del grupo: monto + pendientes, con acento visual de aporte.
class CobrosCard extends StatelessWidget {
  final double montoTotalPendiente;
  final int jugadoresConDeuda;
  final VoidCallback? onVerCobros;
  final bool showAction;

  const CobrosCard({
    super.key,
    required this.montoTotalPendiente,
    required this.jugadoresConDeuda,
    this.onVerCobros,
    this.showAction = true,
  });

  bool get _todosAlDia => jugadoresConDeuda == 0;

  String _pendientesLinea(MatchPayStrings l10n) {
    if (jugadoresConDeuda == 0) return l10n.tr('cobrosCardNoDebts');
    if (jugadoresConDeuda == 1) {
      return l10n.tr('cobrosCardOnePlayerWithDebt');
    }
    return l10n.tr(
      'cobrosCardPlayersWithDebt',
      params: {'count': '$jugadoresConDeuda'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = _todosAlDia
        ? MatchPayTokens.accentSuccess
        : MatchPayTokens.accentUrgent;

    return MatchPaySurfaceCard(
      elevated: true,
      urgent: !_todosAlDia,
      onTap: onVerCobros,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(MatchPayTokens.radiusCard),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _GroupStatusBadge(allPaid: _todosAlDia),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _todosAlDia
                                ? l10n.tr('homeGroupAllPaid')
                                : formatMoney(montoTotalPendiente),
                            style: MatchPayTokens.displayStyle(
                              color: _todosAlDia
                                  ? MatchPayTokens.accentSuccess
                                  : MatchPayTokens.ink,
                            ).copyWith(
                              fontSize: _todosAlDia ? 22 : 32,
                              letterSpacing: -0.7,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _pendientesLinea(l10n),
                            style: MatchPayTokens.bodySmallStyle(
                              color: _todosAlDia
                                  ? MatchPayTokens.accentSuccess
                                  : MatchPayTokens.inkSecondary,
                            ).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (showAction &&
                              onVerCobros != null &&
                              !_todosAlDia) ...[
                            const SizedBox(height: 8),
                            Text(
                              l10n.tr('cobrosCardViewCobros'),
                              style: MatchPayTokens.bodySmallStyle(
                                color: context.sportPrimaryDark,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onVerCobros != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: MatchPayTokens.inkMuted,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupStatusBadge extends StatelessWidget {
  final bool allPaid;

  const _GroupStatusBadge({required this.allPaid});

  @override
  Widget build(BuildContext context) {
    final color = allPaid
        ? MatchPayTokens.accentSuccess
        : MatchPayTokens.accentUrgent;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(
        allPaid
            ? Icons.check_circle_rounded
            : Icons.account_balance_wallet_rounded,
        color: color,
        size: 26,
      ),
    );
  }
}
