import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing/billing_entitlement.dart';
import 'billing/play_billing_client.dart';
import 'billing/play_billing_diag.dart';
import 'billing/play_billing_phase.dart';
import 'billing/play_product_ids.dart';
import 'billing/play_purchase_payload.dart';
import 'billing/play_purchase_validation_result.dart';
import 'billing/play_purchase_validator.dart';

/// Capacidades de suscripción Kloovi Pro (preparado para Play Store).
enum ProFeature { createMatch, automateCharges, viewStatistics, managePlayers }

/// Estado de suscripción / trial / Founder.
///
/// ## Autoridad Pro
/// - `profiles.acceso_ilimitado` (bypass administrativo), o
/// - entitlement de Supabase (`get_my_billing_entitlement` /
///   `validate-play-purchase`).
///
/// `matchpay_pro_active` y allowlists locales de email **no** otorgan Pro.
class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();

  SubscriptionService._({
    PlayBillingClient? playBilling,
    PlayPurchaseValidator? validator,
  }) : _playBillingOverride = playBilling,
       _validatorOverride = validator {
    _wireValidationHandler();
  }

  /// Visible para tests con dependencias inyectadas.
  @visibleForTesting
  factory SubscriptionService.forTesting({
    PlayBillingClient? playBilling,
    PlayPurchaseValidator? validator,
  }) {
    return SubscriptionService._(
      playBilling: playBilling,
      validator: validator,
    );
  }

  final PlayBillingClient? _playBillingOverride;
  final PlayPurchaseValidator? _validatorOverride;
  PlayBillingClient? _playBillingLazy;
  PlayPurchaseValidator? _validatorLazy;

  /// Solo tests: inyecta validator en el singleton [instance].
  @visibleForTesting
  static PlayPurchaseValidator? debugValidatorOverride;

  Future<BillingEntitlement>? _refreshInFlight;

  void _wireValidationHandler() {
    final client = _playBillingOverride ?? _playBillingLazy;
    if (client != null) {
      client.validationHandler = _onPlayNeedsValidation;
    }
  }

  PlayBillingClient get _playBilling {
    final client =
        _playBillingOverride ?? (_playBillingLazy ??= PlayBillingClient());
    client.validationHandler = _onPlayNeedsValidation;
    return client;
  }

  PlayPurchaseValidator get _validator =>
      debugValidatorOverride ??
      _validatorOverride ??
      (_validatorLazy ??= SupabasePlayPurchaseValidator());

  static const _keyProCache = 'matchpay_pro_active';

  bool _accesoIlimitado = false;
  String? _email;
  bool _loaded = false;
  BillingEntitlement _entitlement = BillingEntitlement.none;
  PlayPurchaseValidationResult? _lastValidationResult;

  bool get isLoaded => _loaded;

  BillingEntitlement get entitlement => _entitlement;
  PlayPurchaseValidationResult? get lastValidationResult =>
      _lastValidationResult;

  PlayBillingPhase get playBillingPhase => _playBilling.phase;
  String? get playBillingErrorCode => _playBilling.lastErrorCode;
  String? get playBillingErrorMessage => _playBilling.lastErrorMessage;
  PlayPurchasePayload? get lastPlayPurchasePendingValidation =>
      _playBilling.lastPendingValidation;

  String? playFormattedPrice(String productId) =>
      _playBilling.formattedPriceFor(productId);

  String? get monthlyPlayPrice => playFormattedPrice(PlayProductIds.monthly);

  String? get founderPlayPrice =>
      playFormattedPrice(PlayProductIds.founderAnnual);

  /// Solo bypass administrativo de BD (`acceso_ilimitado`).
  bool get hasUnlimitedAccess => _accesoIlimitado;

  /// Pro oficial: staff/admin o entitlement comercial aún vigente.
  ///
  /// Si `expires_at` ya pasó, no concede Pro aunque `_entitlement.isPro`
  /// siga en true (memoria obsoleta tras cancelación/expiración).
  bool get isPro =>
      hasUnlimitedAccess || _entitlement.grantsCommercialProNow();

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
    // Cache UX se lee solo para compat; no concede Pro.
    final prefs = await SharedPreferences.getInstance();
    prefs.getBool(_keyProCache);
    _loaded = true;
    notifyListeners();

    try {
      await _playBilling.initialize(onChanged: notifyListeners);
    } catch (e, st) {
      debugPrint('SubscriptionService Play Billing init failed: $e\n$st');
      notifyListeners();
    }

    try {
      await refreshEntitlement();
    } catch (_) {
      // Sin sesión o RPC fallida: no inventar Pro.
    }
  }

  /// Sincroniza bypass administrativo desde `profiles`.
  void syncFromProfile({required bool accesoIlimitado, String? email}) {
    final normalized = email?.trim().toLowerCase();
    final changed = _accesoIlimitado != accesoIlimitado || _email != normalized;
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

  /// Limpia entitlement comercial local (logout / delete account).
  Future<void> clearCommercialEntitlement() async {
    _entitlement = BillingEntitlement.none;
    _lastValidationResult = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProCache, false);
  }

  /// Refresca entitlement oficial desde `get_my_billing_entitlement()`.
  ///
  /// Coalescing: llamadas concurrentes comparten un solo RPC.
  /// Si falla la red, relanza el error **sin** borrar el entitlement previo.
  Future<BillingEntitlement> refreshEntitlement() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _refreshEntitlementOnce();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<BillingEntitlement> _refreshEntitlementOnce() async {
    final next = await _validator.fetchEntitlement();
    _entitlement = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProCache, next.isPro);
    return next;
  }

  /// Best-effort para lifecycle / gates: no revoca en error de red.
  Future<void> refreshEntitlementBestEffort() async {
    try {
      await refreshEntitlement();
    } catch (e, st) {
      debugPrint('refreshEntitlementBestEffort failed: $e\n$st');
    }
  }

  /// Aplica un entitlement ya conocido (p.ej. respuesta de validate).
  void applyEntitlement(BillingEntitlement entitlement) {
    _entitlement = entitlement;
    notifyListeners();
  }

  /// @deprecated No otorga Pro. Preferir [clearCommercialEntitlement].
  @Deprecated(
    'No authority for Pro. Use refreshEntitlement/clearCommercialEntitlement.',
  )
  Future<void> setProActive(bool active) async {
    if (!active) {
      await clearCommercialEntitlement();
      return;
    }
    notifyListeners();
  }

  Future<void> reloadPlayProducts() =>
      _playBilling.loadProducts(onChanged: notifyListeners);

  Future<void> purchaseMonthlyTrial() =>
      _playBilling.purchaseMonthlyTrial(onChanged: notifyListeners);

  Future<void> purchaseFounderAnnual() =>
      _playBilling.purchaseFounderAnnual(onChanged: notifyListeners);

  /// Restaura compras Play y las envía al mismo flujo de validación.
  Future<bool> restorePurchases() async {
    await _playBilling.restorePurchases(onChanged: notifyListeners);
    return isPro;
  }

  Future<bool> _onPlayNeedsValidation(
    PlayPurchasePayload payload,
    PurchaseDetails details,
  ) async {
    final result = await _validator.validate(payload);
    _lastValidationResult = result;

    if (!result.ok) {
      _playBilling.reportValidationFailure(
        result.errorCode?.name ?? 'validation_failed',
        result.safeMessage ?? 'validation_failed',
      );
      KlooviBillingDiag.log('entitlement_result', {'is_pro': false});
      notifyListeners();
      return false;
    }

    if (result.entitlement != null) {
      _entitlement = result.entitlement!;
    } else {
      await refreshEntitlement();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProCache, _entitlement.isPro);

    if (result.shouldCompletePurchase && details.pendingCompletePurchase) {
      try {
        await _playBilling.completePurchase(details);
      } catch (e, st) {
        debugPrint('completePurchase after validation failed: $e\n$st');
      }
    }

    KlooviBillingDiag.log('entitlement_result', {'is_pro': isPro});
    notifyListeners();
    return isPro;
  }
}
