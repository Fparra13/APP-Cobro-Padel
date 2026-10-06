import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing/play_billing_client.dart';
import 'billing/play_billing_phase.dart';
import 'billing/play_product_ids.dart';
import 'billing/play_purchase_payload.dart';

/// Capacidades de suscripción Kloovi Pro (preparado para Play Store).
enum ProFeature {
  createMatch,
  automateCharges,
  viewStatistics,
  managePlayers,
}

/// Estado de suscripción / trial / founder.
///
/// ## Entitlement (legacy, no autoridad de compra Play)
/// Acceso desbloqueado si:
/// - `acceso_ilimitado` en profiles (founder/staff), o
/// - email en allowlist local de founder, o
/// - flag Pro/trial local `matchpay_pro_active`.
///
/// ## Google Play Billing (capa nueva)
/// [PlayBillingClient] inicia compras/restore. Una compra Play **no** otorga
/// Pro aquí: falta `validate-play-purchase` + `get_my_billing_entitlement()`.
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();

  SubscriptionService._({PlayBillingClient? playBilling})
      : _playBillingOverride = playBilling;

  /// Visible para tests con cliente inyectado.
  @visibleForTesting
  factory SubscriptionService.forTesting(PlayBillingClient playBilling) {
    return SubscriptionService._(playBilling: playBilling);
  }

  final PlayBillingClient? _playBillingOverride;
  PlayBillingClient? _playBillingLazy;

  PlayBillingClient get _playBilling =>
      _playBillingOverride ?? (_playBillingLazy ??= PlayBillingClient());

  static const _keyProActive = 'matchpay_pro_active';

  /// Dueño / acceso permanente (defensa en cliente; la fuente de verdad es BD).
  static const founderEmails = {'fparram13@gmail.com'};

  bool _proActive = false;
  bool _accesoIlimitado = false;
  String? _email;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  PlayBillingPhase get playBillingPhase => _playBilling.phase;
  String? get playBillingErrorCode => _playBilling.lastErrorCode;
  String? get playBillingErrorMessage => _playBilling.lastErrorMessage;
  PlayPurchasePayload? get lastPlayPurchasePendingValidation =>
      _playBilling.lastPendingValidation;

  String? playFormattedPrice(String productId) =>
      _playBilling.formattedPriceFor(productId);

  String? get monthlyPlayPrice =>
      playFormattedPrice(PlayProductIds.monthly);

  String? get founderPlayPrice =>
      playFormattedPrice(PlayProductIds.founderAnnual);

  bool get hasUnlimitedAccess {
    if (_accesoIlimitado) return true;
    final email = _email;
    if (email == null || email.isEmpty) return false;
    return founderEmails.contains(email);
  }

  /// Pro / trial activo o founder (legacy + staff). No incluye compras Play
  /// pendientes de validación backend.
  bool get isPro => hasUnlimitedAccess || _proActive;

  bool can(ProFeature feature) {
    switch (feature) {
      case ProFeature.createMatch:
      case ProFeature.automateCharges:
      case ProFeature.viewStatistics:
      case ProFeature.managePlayers:
        return isPro;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _proActive = prefs.getBool(_keyProActive) ?? false;
    _loaded = true;
    notifyListeners();

    try {
      await _playBilling.initialize(onChanged: notifyListeners);
    } catch (e, st) {
      debugPrint('SubscriptionService Play Billing init failed: $e\n$st');
      notifyListeners();
    }
  }

  /// Sincroniza entitlements desde `profiles` + email de sesión.
  void syncFromProfile({
    required bool accesoIlimitado,
    String? email,
  }) {
    final normalized = email?.trim().toLowerCase();
    final changed =
        _accesoIlimitado != accesoIlimitado || _email != normalized;
    _accesoIlimitado = accesoIlimitado;
    _email = normalized;
    if (changed) notifyListeners();
  }

  void clearProfileEntitlements() {
    if (!_accesoIlimitado && _email == null) return;
    _accesoIlimitado = false;
    _email = null;
    notifyListeners();
  }

  /// Solo para pruebas / flag local legacy. No usar como resultado de compra Play.
  Future<void> setProActive(bool active) async {
    if (hasUnlimitedAccess) {
      _proActive = true;
      notifyListeners();
      return;
    }
    _proActive = active;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProActive, active);
  }

  Future<void> reloadPlayProducts() =>
      _playBilling.loadProducts(onChanged: notifyListeners);

  Future<void> purchaseMonthlyTrial() =>
      _playBilling.purchaseMonthlyTrial(onChanged: notifyListeners);

  Future<void> purchaseFounderAnnual() =>
      _playBilling.purchaseFounderAnnual(onChanged: notifyListeners);

  /// Restaura compras Play. No otorga Pro; deja payload pendiente de validación.
  Future<bool> restorePurchases() async {
    await _playBilling.restorePurchases(onChanged: notifyListeners);
    // Compat: callers antiguos esperaban bool. True solo si ya hay Pro legacy.
    // Una restore Play exitosa sin validación backend NO implica Pro.
    return isPro;
  }
}
