import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Nudges suaves para conversión jugador → organizador (no invasivos).
class OrganizerNudgeService {
  OrganizerNudgeService._();

  static const _keySnackCount = 'matchpay_organizer_nudge_snack_count';
  static const _maxSnacks = 3;

  static Future<bool> shouldShowHomeCard({
    required int partidosJugados,
    required int invitesRecibidas,
  }) async {
    if (AuthService.instance.isOrganizer) return false;
    if (partidosJugados >= 3 || invitesRecibidas >= 2) return true;
    return false;
  }

  static Future<void> maybeShowAfterConfirm(BuildContext context) async {
    if (AuthService.instance.isOrganizer) return;

    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_keySnackCount) ?? 0;
    if (count >= _maxSnacks) return;

    if (!context.mounted) return;
    final l10n = context.l10n;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MatchPayTokens.ink,
        content: Text(l10n.tr('organizerNudgeSnack')),
        action: SnackBarAction(
          label: l10n.tr('organizerNudgeAction'),
          textColor: MatchPayTokens.accentUrgentBorder,
          onPressed: () => _openBecomeOrganizerDialog(context),
        ),
        duration: const Duration(seconds: 6),
      ),
    );

    await prefs.setInt(_keySnackCount, count + 1);
  }

  static Future<void> _openBecomeOrganizerDialog(BuildContext context) async {
    if (!context.mounted) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('becomeOrganizerTitle')),
        content: Text(l10n.tr('becomeOrganizerBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('becomeOrganizerCta')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AuthService.instance.becomeOrganizer();
      if (!context.mounted) return;
      await context.switchAppUiMode(AppUiMode.organizer);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('becomeOrganizerDone'))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }
}
