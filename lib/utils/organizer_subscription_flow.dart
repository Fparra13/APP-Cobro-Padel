import 'package:flutter/material.dart';

import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/feature_gate.dart';
import '../core/subscription_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Flujo para organizar: paywall/trial → promover rol → shell organizador.
Future<void> openOrganizerSubscriptionFlow(BuildContext context) async {
  if (AuthService.instance.isOrganizer) {
    await context.switchAppUiMode(AppUiMode.organizer);
    return;
  }

  final ok = await FeatureGate.requirePro(
    context,
    feature: ProFeature.createMatch,
    message: context.l10n.tr('becomeOrganizerPaywallMessage'),
  );
  if (!ok || !context.mounted) return;

  try {
    await AuthService.instance.becomeOrganizer();
    await AuthService.instance.refreshProfile();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.userError(e))),
    );
    return;
  }
  if (!context.mounted) return;
  await context.switchAppUiMode(AppUiMode.organizer);
}
