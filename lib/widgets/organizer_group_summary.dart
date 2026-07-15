import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Resumen del grupo en Inicio: monto + pendientes, con icono de aporte.
class OrganizerGroupSummary extends StatelessWidget {
  final int totalJugadores;
  final int jugadoresConDeuda;
  /// Sin deuda neta (incluye saldo a favor).
  final int jugadoresAlDia;
  final double montoPendiente;
  final VoidCallback? onVerCobros;

  const OrganizerGroupSummary({
    super.key,
    required this.totalJugadores,
    required this.jugadoresConDeuda,
    required this.jugadoresAlDia,
    required this.montoPendiente,
    this.onVerCobros,
  });

  bool get _todosAlDia => jugadoresConDeuda == 0;

  String _pendientesLinea(MatchPayStrings l10n) {
    if (jugadoresConDeuda == 0) return l10n.tr('homeNoPendingDebts');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchPaySectionHeader(
          title: l10n.tr('homeGroupSummary'),
          accent: !_todosAlDia,
          pulseDot: !_todosAlDia,
        ),
        const SizedBox(height: 10),
        MatchPaySurfaceCard(
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
                    padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
                    child: Row(
                      children: [
                        _GroupMoneyBadge(allPaid: _todosAlDia),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _todosAlDia
                                    ? l10n.tr('homeGroupAllPaid')
                                    : formatMoney(montoPendiente),
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
                              if (!_todosAlDia && onVerCobros != null) ...[
                                const SizedBox(height: 6),
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
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: Row(
            children: [
              Expanded(
                child: MatchPayStatChip(
                  width: null,
                  icon: Icons.people_rounded,
                  iconColor: MatchPayTokens.inkSecondary,
                  value: '$totalJugadores',
                  label: l10n.tr('homeStatPlayers'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MatchPayStatChip(
                  width: null,
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: jugadoresConDeuda > 0
                      ? MatchPayTokens.accentUrgent
                      : MatchPayTokens.inkMuted,
                  value: '$jugadoresConDeuda',
                  label: l10n.tr('homeStatWithDebt'),
                  borderColor: jugadoresConDeuda > 0
                      ? MatchPayTokens.accentUrgent.withValues(alpha: 0.35)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MatchPayStatChip(
                  width: null,
                  icon: Icons.check_circle_rounded,
                  iconColor: MatchPayTokens.accentSuccess,
                  value: '$jugadoresAlDia',
                  label: l10n.tr('homeStatUpToDate'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupMoneyBadge extends StatelessWidget {
  final bool allPaid;

  const _GroupMoneyBadge({required this.allPaid});

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
        border: Border.all(color: color.withValues(alpha: 0.25)),
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
