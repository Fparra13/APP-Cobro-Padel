import 'package:flutter/material.dart';

import 'subscription_service.dart';
import '../widgets/paywall_sheet.dart';

/// Puerta de acceso a funciones Pro de Kloovi.
///
/// Depende del entitlement Pro ([SubscriptionService.can]), nunca del rol
/// Organizer. Mostrar el paywall no concede Pro: solo continúa si ya hay
/// capacidad Pro o si el sheet cierra con éxito explícito (hoy scaffolding;
/// la compra real es una fase posterior de Billing).
class FeatureGate {
  FeatureGate._();

  /// True si hay capacidad Pro para [feature].
  ///
  /// Si no, muestra el paywall. Un cierre/cancelación del sheet no implica Pro.
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
