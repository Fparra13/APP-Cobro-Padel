import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import 'matchpay_ui.dart';

/// Tarjeta neutra de cobranza: título + monto + jugadores con deuda.
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

  Color get _accentColor {
    if (jugadoresConDeuda == 0) return MatchPayTokens.inkMuted;
    if (jugadoresConDeuda >= 6) return MatchPayTokens.accentError;
    return MatchPayTokens.accentUrgent;
  }

  String _jugadoresLinea(MatchPayStrings l10n) {
    if (jugadoresConDeuda == 0) return l10n.tr('cobrosCardNoDebts');
    if (jugadoresConDeuda == 1) return l10n.tr('cobrosCardOnePlayerWithDebt');
    return l10n.tr(
      'cobrosCardPlayersWithDebt',
      params: {'count': '$jugadoresConDeuda'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = _accentColor;

    return MatchPaySurfaceCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(MatchPayTokens.radiusCard),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.tr('cobrosCardTitle'),
                      style: MatchPayTokens.titleSmallStyle(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      formatMoney(montoTotalPendiente),
                      style: MatchPayTokens.statValueStyle().copyWith(
                        fontSize: 32,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('cobrosCardAmountLabel'),
                      style: MatchPayTokens.bodySmallStyle(),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _jugadoresLinea(l10n),
                      style: MatchPayTokens.bodySmallStyle(color: accent)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (showAction) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: onVerCobros,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              MatchPayTokens.radiusButton,
                            ),
                          ),
                        ),
                        child: Text(l10n.tr('cobrosCardViewCobros')),
                      ),
                    ],
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
