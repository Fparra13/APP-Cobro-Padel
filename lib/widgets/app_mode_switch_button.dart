import 'package:flutter/material.dart';

import '../core/app_settings_controller.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';

/// Cambio organizador ↔ jugador con badge de pendientes del otro rol.
class AppModeSwitchButton extends StatelessWidget {
  final AppUiMode targetMode;
  final int pendingCount;
  final VoidCallback onPressed;

  const AppModeSwitchButton({
    super.key,
    required this.targetMode,
    required this.pendingCount,
    required this.onPressed,
  });

  bool get _toPlayer => targetMode == AppUiMode.player;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tooltip = pendingCount > 0
        ? l10n.tr(
            _toPlayer
                ? 'appModeSwitchToPlayerPending'
                : 'appModeSwitchToOrganizerPending',
            params: {'count': '$pendingCount'},
          )
        : l10n.tr(
            _toPlayer ? 'appModeSwitchToPlayer' : 'appModeSwitchToOrganizer',
          );

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: pendingCount > 0,
        label: Text(
          pendingCount > 9 ? '9+' : '$pendingCount',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: MatchPayTokens.accentError,
        child: Icon(
          _toPlayer
              ? Icons.person_outline_rounded
              : Icons.swap_horiz_rounded,
          color: MatchPayTokens.inkMuted,
        ),
      ),
    );
  }
}
