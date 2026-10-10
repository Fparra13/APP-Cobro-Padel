import 'package:flutter/material.dart';

import 'subscription_service.dart';
import '../widgets/paywall_sheet.dart';

/// Puerta de acceso a funciones Pro de Kloovi.
///
/// Depende del entitlement Pro ([SubscriptionService.can]):
/// `acceso_ilimitado` o billing backend. Nunca del rol Organizer.
/// El paywall solo retorna true tras validación backend exitosa con Pro.
class FeatureGate {
  FeatureGate._();

  /// True si hay capacidad Pro para [feature].
  ///
  /// Antes de autorizar, refresca el entitlement desde Supabase.
  /// - RPC `is_pro = false` → actualiza estado y muestra paywall.
  /// - Error de red → no borra el entitlement; aplica expiración local
  ///   vía [SubscriptionService.isPro] (no concede si `expires_at` ya pasó).
  /// Un cierre/cancelación del sheet no implica Pro.
  static Future<bool> requirePro(
    BuildContext context, {
    required ProFeature feature,
    String? message,
  }) async {
    await SubscriptionService.instance.refreshEntitlementBestEffort();
    if (SubscriptionService.instance.can(feature)) return true;
    if (!context.mounted) return false;
    final accepted = await showPaywallSheet(
      context,
      feature: feature,
      message: message,
    );
    return accepted == true;
  }
}
