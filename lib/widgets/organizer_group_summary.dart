import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import 'matchpay_ui.dart';

/// Resumen del grupo en el home del organizador: monto pendiente + 3 fichas.
class OrganizerGroupSummary extends StatelessWidget {
  final int totalJugadores;
  final int jugadoresConDeuda;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchPaySectionHeader(title: l10n.tr('homeGroupSummary')),
        const SizedBox(height: 10),
        MatchPaySurfaceCard(
          elevated: true,
          onTap: onVerCobros,
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _todosAlDia
                        ? [
                            MatchPayTokens.accentSuccessBg,
                            MatchPayTokens.accentSuccess.withValues(alpha: 0.18),
                          ]
                        : [
                            MatchPayTokens.accentUrgentBg,
                            MatchPayTokens.accentUrgent.withValues(alpha: 0.14),
                          ],
                  ),
                  borderRadius:
                      BorderRadius.circular(MatchPayTokens.radiusChip),
                ),
                child: Icon(
                  _todosAlDia
                      ? Icons.check_circle_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: _todosAlDia
                      ? MatchPayTokens.accentSuccess
                      : MatchPayTokens.accentUrgent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _todosAlDia
                          ? l10n.tr('homeGroupAllPaid')
                          : l10n.tr('homeGroupSummary'),
                      style: MatchPayTokens.titleMediumStyle(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _todosAlDia
                          ? l10n.tr('homeNoPendingDebts')
                          : l10n.tr(
                              'homeAmountToCollect',
                              params: {'amount': formatMoney(montoPendiente)},
                            ),
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        color: _todosAlDia
                            ? MatchPayTokens.accentSuccess
                            : MatchPayTokens.inkMuted,
                        fontWeight:
                            _todosAlDia ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (onVerCobros != null && !_todosAlDia)
                Icon(
                  Icons.chevron_right_rounded,
                  color: MatchPayTokens.inkMuted.withValues(alpha: 0.7),
                ),
            ],
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
                  iconColor: MatchPayTokens.accentUrgent,
                  value: '$totalJugadores',
                  label: l10n.tr('homeStatPlayers'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MatchPayStatChip(
                  width: null,
                  icon: Icons.warning_amber_rounded,
                  iconColor: MatchPayTokens.accentError,
                  value: '$jugadoresConDeuda',
                  label: l10n.tr('homeStatWithDebt'),
                  borderColor: jugadoresConDeuda > 0
                      ? MatchPayTokens.accentError.withValues(alpha: 0.35)
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
