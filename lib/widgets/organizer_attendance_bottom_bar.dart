import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Composición visual del bottom Attendance (CTAs + slot DecisionPanel).
///
/// No conoce Supabase ni dominio. El screen resuelve condiciones y callbacks.
class OrganizerAttendanceBottomBar extends StatelessWidget {
  /// Si true, muestra [decisionPanel] y no el stack de CTAs.
  final bool showDecisionPanel;
  final Widget? decisionPanel;

  /// Si true (y no hay decision), no pinta Recordar/WhatsApp/hint.
  final bool hideActions;

  final bool showAutoConfirmHint;
  final bool canRemind;
  final bool canShowWhatsApp;
  final VoidCallback onRemind;
  final VoidCallback onWhatsApp;

  const OrganizerAttendanceBottomBar({
    super.key,
    this.showDecisionPanel = false,
    this.decisionPanel,
    this.hideActions = false,
    this.showAutoConfirmHint = false,
    this.canRemind = false,
    this.canShowWhatsApp = false,
    required this.onRemind,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    if (showDecisionPanel) {
      return decisionPanel ?? const SizedBox.shrink();
    }
    if (hideActions) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: canRemind ? onRemind : null,
          icon: const Icon(Icons.campaign_rounded),
          label: Text(l10n.tr('asistenciasRemindPending')),
          style: FilledButton.styleFrom(
            backgroundColor: context.sportPalette.primary,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
            ),
          ),
        ),
        if (canShowWhatsApp) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onWhatsApp,
            icon: const Icon(
              Icons.chat_outlined,
              color: Color(0xFF25D366),
            ),
            label: Text(l10n.tr('organizeWhatsAppNoAppButton')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: const Color(0xFF1B8F4E),
              side: const BorderSide(color: Color(0xFF25D366)),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(MatchPayTokens.radiusButton),
              ),
            ),
          ),
        ],
        if (showAutoConfirmHint)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.tr('organizeAutoConfirmInProgress'),
              style: MatchPayTokens.titleSmallStyle(
                color: MatchPayTokens.accentUrgent,
              ).copyWith(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
