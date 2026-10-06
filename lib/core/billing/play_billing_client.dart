import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'play_billing_phase.dart';
import 'play_offer_selection.dart';
import 'play_product_ids.dart';
import 'play_purchase_payload.dart';

/// Abstracción mínima sobre la tienda (permite tests sin Google Play).
abstract class PlayBillingStore {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers);
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails purchase);
}

class InAppPurchaseBillingStore implements PlayBillingStore {
  InAppPurchaseBillingStore([InAppPurchase? iap]) : _iapOverride = iap;

  final InAppPurchase? _iapOverride;

  /// Lazy: evitar registrar el plugin Android solo por construir SubscriptionService.
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) =>
      _iap.queryProductDetails(identifiers);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _iap.buyNonConsumable(purchaseParam: purchaseParam);

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}

/// Único propietario del [InAppPurchase.instance.purchaseStream].
///
/// No otorga Pro. No llama a `completePurchase` hasta validación backend (fase
/// posterior). Compra → extrae token → fase `*NeedsValidation`.
class PlayBillingClient {
  PlayBillingClient({PlayBillingStore? store})
      : _store = store ?? InAppPurchaseBillingStore();

  final PlayBillingStore _store;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  PlayBillingPhase _phase = PlayBillingPhase.idle;
  String? _lastErrorCode;
  String? _lastErrorMessage;
  PlayPurchasePayload? _lastPendingValidation;
  List<ProductDetails> _products = const [];
  bool _initialized = false;

  /// Contador de completePurchase (tests: debe permanecer 0 en 8B-1).
  int completePurchaseCallCount = 0;

  PlayBillingPhase get phase => _phase;
  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorMessage => _lastErrorMessage;
  PlayPurchasePayload? get lastPendingValidation => _lastPendingValidation;
  List<ProductDetails> get products => List.unmodifiable(_products);
  bool get isInitialized => _initialized;

  String? formattedPriceFor(String productId) {
    for (final p in _products) {
      if (p.id == productId) return p.price;
    }
    return null;
  }

  Future<void> initialize({VoidCallback? onChanged}) async {
    if (_initialized) return;
    _purchaseSub = _store.purchaseStream.listen(
      (purchases) => _onPurchases(purchases, onChanged),
      onError: (Object e, StackTrace st) {
        debugPrint('PlayBillingClient.purchaseStream error: $e');
        _setError('purchase_stream_error', e.toString(), onChanged);
      },
    );
    _initialized = true;
    await loadProducts(onChanged: onChanged);
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialized = false;
  }

  Future<void> loadProducts({VoidCallback? onChanged}) async {
    _phase = PlayBillingPhase.loadingProducts;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();

    try {
      final available = await _store.isAvailable();
      if (!available) {
        _products = const [];
        _phase = PlayBillingPhase.unavailable;
        _lastErrorCode = 'store_unavailable';
        _lastErrorMessage = 'Google Play Billing no está disponible.';
        onChanged?.call();
        return;
      }

      final response = await _store.queryProductDetails(PlayProductIds.all);
      if (response.error != null) {
        _products = const [];
        _phase = PlayBillingPhase.purchaseError;
        _lastErrorCode = response.error!.code;
        _lastErrorMessage = response.error!.message;
        onChanged?.call();
        return;
      }

      _products = List<ProductDetails>.from(response.productDetails);
      if (response.notFoundIDs.isNotEmpty || _products.isEmpty) {
        _phase = PlayBillingPhase.configurationError;
        _lastErrorCode = 'products_not_found';
        _lastErrorMessage =
            'Productos no encontrados: ${response.notFoundIDs.join(', ')}';
        onChanged?.call();
        return;
      }

      _phase = PlayBillingPhase.productsLoaded;
      onChanged?.call();
    } catch (e) {
      _products = const [];
      _setError('load_products_failed', e.toString(), onChanged);
    }
  }

  Future<void> purchaseMonthlyTrial({VoidCallback? onChanged}) async {
    await _purchaseSelected(
      select: PlayOfferSelection.selectMonthlyTrial,
      onChanged: onChanged,
    );
  }

  Future<void> purchaseFounderAnnual({VoidCallback? onChanged}) async {
    await _purchaseSelected(
      select: PlayOfferSelection.selectFounderAnnual,
      onChanged: onChanged,
    );
  }

  Future<void> restorePurchases({VoidCallback? onChanged}) async {
    final available = await _store.isAvailable();
    if (!available) {
      _setPhase(
        PlayBillingPhase.unavailable,
        code: 'store_unavailable',
        message: 'Google Play Billing no está disponible.',
        onChanged: onChanged,
      );
      return;
    }

    _phase = PlayBillingPhase.restorePending;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();

    try {
      await _store.restorePurchases();
    } catch (e) {
      _setError('restore_failed', e.toString(), onChanged);
    }
  }

  /// Expone candidatos desde productos cargados (también útil en tests).
  List<PlayOfferCandidate> offerCandidatesFrom(List<ProductDetails> products) {
    final out = <PlayOfferCandidate>[];
    for (final details in products) {
      if (details is! GooglePlayProductDetails) continue;
      final index = details.subscriptionIndex;
      final offers = details.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index < 0 || index >= offers.length) {
        continue;
      }
      final offer = offers[index];
      final token = (details.offerToken ?? offer.offerIdToken).trim();
      if (token.isEmpty) continue;

      out.add(
        PlayOfferCandidate(
          productId: details.id,
          basePlanId: offer.basePlanId,
          offerId: offer.offerId,
          offerToken: token,
          hasFreeTrialPhase: _hasFreeTrial(offer.pricingPhases),
          hasIntroductoryPricePhase: _hasIntroductoryPrice(offer.pricingPhases),
          sourceProductDetails: details,
        ),
      );
    }
    return out;
  }

  Future<void> _purchaseSelected({
    required PlayOfferCandidate Function(Iterable<PlayOfferCandidate>) select,
    VoidCallback? onChanged,
  }) async {
    final available = await _store.isAvailable();
    if (!available) {
      _setPhase(
        PlayBillingPhase.unavailable,
        code: 'store_unavailable',
        message: 'Google Play Billing no está disponible.',
        onChanged: onChanged,
      );
      return;
    }

    if (_products.isEmpty) {
      await loadProducts(onChanged: onChanged);
    }
    if (_phase == PlayBillingPhase.unavailable ||
        _phase == PlayBillingPhase.configurationError) {
      return;
    }

    late final PlayOfferCandidate selected;
    try {
      selected = select(offerCandidatesFrom(_products));
    } on PlayBillingConfigurationException catch (e) {
      _setPhase(
        PlayBillingPhase.configurationError,
        code: e.code,
        message: e.message,
        onChanged: onChanged,
      );
      return;
    }

    final productDetails = selected.sourceProductDetails;
    if (productDetails is! GooglePlayProductDetails) {
      _setPhase(
        PlayBillingPhase.configurationError,
        code: 'invalid_product_details',
        message: 'La oferta seleccionada no es GooglePlayProductDetails.',
        onChanged: onChanged,
      );
      return;
    }

    _phase = PlayBillingPhase.purchasePending;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();

    try {
      final ok = await _store.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: productDetails,
          offerToken: selected.offerToken,
        ),
      );
      if (!ok) {
        _setError(
          'buy_non_consumable_rejected',
          'Google Play rechazó iniciar la compra.',
          onChanged,
        );
      }
    } catch (e) {
      _setError('buy_failed', e.toString(), onChanged);
    }
  }

  /// Procesa updates del purchaseStream (también usable en tests).
  @visibleForTesting
  void handlePurchasesForTest(
    List<PurchaseDetails> purchases, {
    VoidCallback? onChanged,
  }) {
    _onPurchases(purchases, onChanged);
  }

  void _onPurchases(
    List<PurchaseDetails> purchases,
    VoidCallback? onChanged,
  ) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _phase = PlayBillingPhase.purchasePending;
          onChanged?.call();
        case PurchaseStatus.canceled:
          _setPhase(
            PlayBillingPhase.idle,
            code: 'purchase_canceled',
            message: 'Compra cancelada.',
            onChanged: onChanged,
          );
        case PurchaseStatus.error:
          _setError(
            purchase.error?.code ?? 'purchase_error',
            purchase.error?.message ?? 'Error de compra.',
            onChanged,
          );
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // NO completePurchase. NO otorgar Pro.
          final payload = PlayPurchasePayload.fromPurchaseDetails(purchase);
          if (payload == null) {
            _setError(
              'missing_purchase_token',
              'La compra no incluye purchase_token.',
              onChanged,
            );
            continue;
          }
          _lastPendingValidation = payload;
          debugPrint(
            'PlayBillingClient: ${purchase.status.name} needs validation '
            'product=${payload.productId} '
            'pendingComplete=${payload.pendingCompletePurchase}',
          );
          _phase = purchase.status == PurchaseStatus.restored
              ? PlayBillingPhase.restoreNeedsValidation
              : PlayBillingPhase.purchaseNeedsValidation;
          onChanged?.call();
          // Intencionalmente NO se llama completePurchase aquí.
          if (purchase.pendingCompletePurchase) {
            debugPrint(
              'PlayBillingClient: deferring completePurchase until backend '
              'validation (8B-2).',
            );
          }
      }
    }
  }

  /// Solo para la futura fase de validación backend. No usar en 8B-1 UI.
  @visibleForTesting
  Future<void> completePurchaseForTests(PurchaseDetails details) async {
    completePurchaseCallCount++;
    await _store.completePurchase(details);
  }

  void _setError(String code, String message, VoidCallback? onChanged) {
    _phase = PlayBillingPhase.purchaseError;
    _lastErrorCode = code;
    _lastErrorMessage = message;
    onChanged?.call();
  }

  void _setPhase(
    PlayBillingPhase phase, {
    String? code,
    String? message,
    VoidCallback? onChanged,
  }) {
    _phase = phase;
    _lastErrorCode = code;
    _lastErrorMessage = message;
    onChanged?.call();
  }

  static bool _hasFreeTrial(List<PricingPhaseWrapper> phases) {
    return phases.any((p) => p.priceAmountMicros == 0);
  }

  static bool _hasIntroductoryPrice(List<PricingPhaseWrapper> phases) {
    if (phases.length < 2) return false;
    final first = phases.first;
    return first.priceAmountMicros > 0 &&
        first.recurrenceMode == RecurrenceMode.finiteRecurring;
  }
}
