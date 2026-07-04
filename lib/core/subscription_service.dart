import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Capacidades de suscripción MatchPay Pro (preparado para Play Store).
enum ProFeature {
  createMatch,
  automateCharges,
  viewStatistics,
  managePlayers,
}

/// Estado de suscripción. Stub local hasta integrar billing.
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const _keyProActive = 'matchpay_pro_active';

  bool _proActive = false;
  bool _loaded = false;

  bool get isPro => _proActive;
  bool get isLoaded => _loaded;

  bool can(ProFeature feature) {
    switch (feature) {
      // Libre hasta integrar Play Billing (paywall era solo un stub).
      case ProFeature.createMatch:
        return true;
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
  }

  /// Solo para pruebas / futura activación tras compra.
  Future<void> setProActive(bool active) async {
    _proActive = active;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProActive, active);
  }

  Future<bool> restorePurchases() async {
    // Placeholder: integrar in_app_purchase / RevenueCat aquí.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return isPro;
  }
}
