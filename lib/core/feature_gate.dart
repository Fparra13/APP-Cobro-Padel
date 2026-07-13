import 'package:flutter/material.dart';

import 'subscription_service.dart';
import '../widgets/paywall_sheet.dart';

/// Puerta de acceso a funciones Pro de Kloovi.
class FeatureGate {
  FeatureGate._();

  /// Devuelve true si el usuario puede continuar (Pro o aceptó paywall).
  static Future<bool> requirePro(
    BuildContext context, {
    required ProFeature feature,
    String? message,
  }) async {
    if (SubscriptionService.instance.can(feature)) return true;
    final accepted = await showPaywallSheet(
      context,
      feature: feature,
      message: message,
    );
    return accepted == true;
  }
}
