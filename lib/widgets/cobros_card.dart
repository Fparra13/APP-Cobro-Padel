import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import 'matchpay_ui.dart';

enum _CobrosCardTone { upToDate, attention, urgent }

/// Tarjeta de cobranza del grupo: estado + monto pendiente + jugadores con deuda.
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

  _CobrosCardTone get _tone {
    if (jugadoresConDeuda == 0) return _CobrosCardTone.upToDate;
    if (jugadoresConDeuda >= 6) return _CobrosCardTone.urgent;
    return _CobrosCardTone.attention;
  }

  Color _accentColor(_CobrosCardTone tone) {
    return switch (tone) {
      _CobrosCardTone.upToDate => MatchPayTokens.accentSuccess,
      _CobrosCardTone.attention => MatchPayTokens.accentUrgent,
      _CobrosCardTone.urgent => MatchPayTokens.accentError,
    };
  }

  Color _surfaceColor(_CobrosCardTone tone) {
    return switch (tone) {
      _CobrosCardTone.upToDate => MatchPayTokens.accentSuccessBg,
      _CobrosCardTone.attention => MatchPayTokens.accentUrgentBg,
      _CobrosCardTone.urgent => MatchPayTokens.accentErrorBg,
    };
  }

  Color _borderColor(_CobrosCardTone tone) {
    return switch (tone) {
      _CobrosCardTone.upToDate =>
        MatchPayTokens.accentSuccess.withValues(alpha: 0.35),
      _CobrosCardTone.attention =>
        MatchPayTokens.accentUrgentBorder.withValues(alpha: 0.7),
      _CobrosCardTone.urgent =>
        MatchPayTokens.accentError.withValues(alpha: 0.45),
    };
  }

  IconData _icon(_CobrosCardTone tone, int jugadores) {
    if (tone == _CobrosCardTone.upToDate) {
      return Icons.check_circle_rounded;
    }
    if (jugadores == 1) return Icons.person_outline_rounded;
    if (tone == _CobrosCardTone.urgent) {
      return Icons.warning_amber_rounded;
    }
    return Icons.payments_outlined;
  }

  String _headline(MatchPayStrings l10n, _CobrosCardTone tone) {
    return switch (tone) {
      _CobrosCardTone.upToDate => l10n.tr('cobrosCardStateUpToDate'),
      _CobrosCardTone.attention => jugadoresConDeuda == 1
          ? l10n.tr('cobrosCardStateOnePending')
          : l10n.tr('cobrosCardStateRecover'),
      _CobrosCardTone.urgent => l10n.tr('cobrosCardStateUrgent'),
    };
  }

  String _scaleLine(MatchPayStrings l10n) {
    if (jugadoresConDeuda == 0) {
      return l10n.tr('cobrosCardNoDebts');
    }
    if (jugadoresConDeuda == 1) {
      return l10n.tr('cobrosCardOnePlayerWithDebt');
    }
    return l10n.tr(
      'cobrosCardPlayersWithDebt',
      params: {'count': '$jugadoresConDeuda'},
    );
  }

  String _ctaLabel(MatchPayStrings l10n, _CobrosCardTone tone) {
    return switch (tone) {
      _CobrosCardTone.upToDate => l10n.tr('cobrosCardViewCobros'),
      _CobrosCardTone.attention => jugadoresConDeuda == 1
          ? l10n.tr('cobrosCardCollectNow')
          : l10n.tr('cobrosCardGoCollect'),
      _CobrosCardTone.urgent => l10n.tr('cobrosCardGoCollect'),
    };
  }

  double _amountFontSize() {
    if (montoTotalPendiente <= 0) return 28;
    if (montoTotalPendiente >= 100000) return 34;
    if (montoTotalPendiente >= 50000) return 32;
    return 30;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tone = _tone;
    final accent = _accentColor(tone);
    final surface = _surfaceColor(tone);
    final border = _borderColor(tone);

    return MatchPaySurfaceCard(
      elevated: tone != _CobrosCardTone.upToDate,
      urgent: tone == _CobrosCardTone.urgent,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
          border: Border.all(color: border, width: 1.25),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius:
                          BorderRadius.circular(MatchPayTokens.radiusChip),
                    ),
                    child: Icon(
                      _icon(tone, jugadoresConDeuda),
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _headline(l10n, tone),
                      style: MatchPayTokens.titleMediumStyle(color: accent)
                          .copyWith(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                formatMoney(montoTotalPendiente),
                style: MatchPayTokens.statValueStyle().copyWith(
                  fontSize: _amountFontSize(),
                  letterSpacing: -0.8,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.tr('cobrosCardAmountLabel'),
                style: MatchPayTokens.bodySmallStyle(),
              ),
              const SizedBox(height: 10),
              Text(
                _scaleLine(l10n),
                style: MatchPayTokens.bodySmallStyle(color: accent).copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              if (showAction) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onVerCobros,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: tone == _CobrosCardTone.upToDate
                        ? MatchPayTokens.inkSecondary
                        : accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(MatchPayTokens.radiusButton),
                    ),
                  ),
                  child: Text(_ctaLabel(l10n, tone)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
