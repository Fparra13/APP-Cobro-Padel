import 'package:flutter/material.dart';

import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../core/feature_gate.dart';
import '../core/subscription_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Abre el paywall para organizar. No cambia el rol en BD (eso va con la suscripción).
Future<void> openOrganizerSubscriptionFlow(BuildContext context) async {
  if (AuthService.instance.isOrganizer) {
    await context.switchAppUiMode(AppUiMode.organizer);
    return;
  }

  await FeatureGate.requirePro(
    context,
    feature: ProFeature.createMatch,
    message: context.l10n.tr('becomeOrganizerPaywallMessage'),
  );
}
