import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/convocatoria_cupo_actions.dart';
import '../utils/matchpay_context.dart';

/// Reprogramar / cancelar cuando el cupo ya no se puede llenar (modo claro).
class ConvocatoriaDecisionPanel extends StatelessWidget {
  final int? partidoId;
  /// Tras reprogramar con éxito (y cancelar si no hay [onCancelSuccess]).
  final VoidCallback? onCompleted;
  /// Tras cancelar con éxito. Si es null, se usa [onCompleted].
  final VoidCallback? onCancelSuccess;
  final VoidCallback? onReschedule;
  final VoidCallback? onCancel;
  final String? message;
  final bool showHeader;

  const ConvocatoriaDecisionPanel({
    super.key,
    this.partidoId,
    this.onCompleted,
    this.onCancelSuccess,
    this.onReschedule,
    this.onCancel,
    this.message,
    this.showHeader = true,
  });

  void _handleReschedule() {
    if (partidoId != null) {
      ConvocatoriaCupoActions.scheduleReprogramar(
        partidoId!,
        onSuccess: onCompleted,
      );
      return;
    }
    if (onReschedule == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => onReschedule!());
  }

  void _handleCancel() {
    if (partidoId != null) {
      ConvocatoriaCupoActions.scheduleCancelar(
        partidoId!,
        onSuccess: onCancelSuccess ?? onCompleted,
      );
      return;
    }
    if (onCancel == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => onCancel!());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return Container(
      padding: EdgeInsets.all(showHeader ? 16 : 0),
      decoration: showHeader
          ? BoxDecoration(
              color: MatchPayTokens.accentUrgentBg,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
              border: Border.all(
                color: MatchPayTokens.accentUrgentBorder.withValues(alpha: 0.45),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.groups_2_outlined,
                  color: MatchPayTokens.accentUrgent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr('organizerCycleAtRiskTitle'),
                        style: MatchPayTokens.titleSmallStyle(
                          color: MatchPayTokens.accentUrgent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message ?? l10n.tr('organizerCycleAtRiskBody'),
                        style: MatchPayTokens.bodySmallStyle(
                          color: MatchPayTokens.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tr('organizerCycleAtRiskAction'),
                        style: MatchPayTokens.bodySmallStyle(
                          color: MatchPayTokens.inkSecondary,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          _actionColumn(context, palette),
        ],
      ),
    );
  }

  Widget _actionColumn(BuildContext context, SportThemePalette palette) {
    final l10n = context.l10n;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _handleReschedule,
          style: FilledButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            elevation: 0,
            shape: buttonShape,
          ),
          icon: const Icon(Icons.event_repeat_rounded, size: 20),
          label: Text(l10n.tr('organizerCycleAtRiskReschedule')),
        ),
        if (onCancel != null || partidoId != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _handleCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: MatchPayTokens.accentError,
              backgroundColor: MatchPayTokens.accentErrorBg,
              side: BorderSide(
                color: MatchPayTokens.accentError.withValues(alpha: 0.55),
              ),
              minimumSize: const Size.fromHeight(48),
              shape: buttonShape,
            ),
            icon: const Icon(Icons.cancel_outlined, size: 20),
            label: Text(l10n.tr('organizerCycleAtRiskCancel')),
          ),
        ],
      ],
    );
  }
}
