import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Capacidades de suscripción Kloovi Pro (preparado para Play Store).
enum ProFeature {
  createMatch,
  automateCharges,
  viewStatistics,
  managePlayers,
}

/// Estado de suscripción / trial / founder.
///
/// Acceso desbloqueado si:
/// - `acceso_ilimitado` en profiles (founder/staff), o
/// - email en allowlist local de founder, o
/// - flag Pro/trial local (hasta integrar Play Billing).
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const _keyProActive = 'matchpay_pro_active';

  /// Dueño / acceso permanente (defensa en cliente; la fuente de verdad es BD).
  static const founderEmails = {'fparram13@gmail.com'};

  bool _proActive = false;
  bool _accesoIlimitado = false;
  String? _email;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  bool get hasUnlimitedAccess {
    if (_accesoIlimitado) return true;
    final email = _email;
    if (email == null || email.isEmpty) return false;
    return founderEmails.contains(email);
  }

  /// Pro / trial activo o founder.
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

  /// Solo para pruebas / futura activación tras compra o trial.
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

  Future<bool> restorePurchases() async {
    // Sin Play Billing: no hay compras que restaurar.
    return isPro;
  }
}
