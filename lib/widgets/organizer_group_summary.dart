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

  String _debtPlayersLine(MatchPayStrings l10n) {
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
          child: Row(
            children: [
              _SummaryIconBadge(allPaid: _todosAlDia),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _todosAlDia
                          ? l10n.tr('homeGroupAllPaid')
                          : l10n.tr(
                              'homeAmountToCollect',
                              params: {
                                'amount': formatMoney(montoPendiente),
                              },
                            ),
                      style: _todosAlDia
                          ? MatchPayTokens.titleMediumStyle()
                          : MatchPayTokens.displayStyle(
                              color: MatchPayTokens.accentUrgent,
                            ).copyWith(fontSize: 22, height: 1.15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _todosAlDia
                          ? l10n.tr('homeNoPendingDebts')
                          : _debtPlayersLine(l10n),
                      style: MatchPayTokens.bodySmallStyle().copyWith(
                        color: _todosAlDia
                            ? MatchPayTokens.accentSuccess
                            : MatchPayTokens.inkSecondary,
                        fontWeight:
                            _todosAlDia ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (!_todosAlDia && onVerCobros != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        l10n.tr('cobrosCardViewCobros'),
                        style: MatchPayTokens.bodySmallStyle(
                          color: MatchPayTokens.accentUrgent,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              if (onVerCobros != null && !_todosAlDia)
                Icon(
                  Icons.chevron_right_rounded,
                  color: MatchPayTokens.accentUrgent.withValues(alpha: 0.65),
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

/// Icono del resumen: check estático si al día; cobros con pulso suave si hay deuda.
class _SummaryIconBadge extends StatefulWidget {
  final bool allPaid;

  const _SummaryIconBadge({required this.allPaid});

  @override
  State<_SummaryIconBadge> createState() => _SummaryIconBadgeState();
}

class _SummaryIconBadgeState extends State<_SummaryIconBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _SummaryIconBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allPaid != widget.allPaid) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (!widget.allPaid) {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat(reverse: true);
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allPaid = widget.allPaid;
    final gradient = allPaid
        ? [
            MatchPayTokens.accentSuccessBg,
            MatchPayTokens.accentSuccess.withValues(alpha: 0.18),
          ]
        : [
            MatchPayTokens.accentUrgentBg,
            MatchPayTokens.accentUrgent.withValues(alpha: 0.14),
          ];
    final iconColor = allPaid
        ? MatchPayTokens.accentSuccess
        : MatchPayTokens.accentUrgent;
    final icon = allPaid
        ? Icons.check_circle_rounded
        : Icons.payments_outlined;

    Widget iconWidget = Icon(icon, color: iconColor, size: 28);

    if (!allPaid && _controller != null) {
      iconWidget = ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.08).animate(
          CurvedAnimation(parent: _controller!, curve: Curves.easeInOut),
        ),
        child: iconWidget,
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
      ),
      child: Center(child: iconWidget),
    );
  }
}
