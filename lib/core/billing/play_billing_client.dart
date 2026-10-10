import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'play_billing_diag.dart';
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

/// Callback async para validar una compra Play (Edge Function).
typedef PlayPurchaseValidationHandler =
    Future<bool> Function(PlayPurchasePayload payload, PurchaseDetails details);

/// Único propietario del [InAppPurchase.instance.purchaseStream].
///
/// No otorga Pro. No llama a `completePurchase` hasta validación backend
/// exitosa. Compra → token → validación → completePurchase si OK.
class PlayBillingClient {
  PlayBillingClient({
    PlayBillingStore? store,
    PlayPurchaseValidationHandler? validationHandler,
    this.restoreEventGrace = const Duration(seconds: 2),
    this.validationTimeout = const Duration(seconds: 45),
  }) : _store = store ?? InAppPurchaseBillingStore() {
    _validationHandler = validationHandler;
  }

  final PlayBillingStore _store;
  PlayPurchaseValidationHandler? _validationHandler;

  /// Espera acotada a eventos del stream tras `restorePurchases()`.
  final Duration restoreEventGrace;

  /// Tope de espera de UI para la validación backend (la Future sigue viva).
  final Duration validationTimeout;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  PlayBillingPhase _phase = PlayBillingPhase.idle;
  String? _lastErrorCode;
  String? _lastErrorMessage;
  PlayPurchasePayload? _lastPendingValidation;
  PurchaseDetails? _lastPendingDetails;
  List<ProductDetails> _products = const [];
  bool _initialized = false;
  bool _validationInFlight = false;

  /// Invalida esperas de restore/validación al iniciar otra operación.
  int _restoreSession = 0;
  int _validationSession = 0;

  /// Contador de completePurchase (tests).
  int completePurchaseCallCount = 0;

  PlayBillingPhase get phase => _phase;
  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorMessage => _lastErrorMessage;
  PlayPurchasePayload? get lastPendingValidation => _lastPendingValidation;
  PurchaseDetails? get lastPendingDetails => _lastPendingDetails;
  List<ProductDetails> get products => List.unmodifiable(_products);
  bool get isInitialized => _initialized;

  /// Inyecta/reemplaza el handler de validación backend (tests / wiring).
  set validationHandler(PlayPurchaseValidationHandler? handler) {
    _validationHandler = handler;
  }

  /// Precio localizado de la oferta que realmente se compra (no el primer
  /// ProductDetails del mismo productId, que puede ser otro base plan).
  String? formattedPriceFor(String productId) {
    final candidates = offerCandidatesFrom(_products);
    try {
      if (productId == PlayProductIds.founderAnnual) {
        final selected = PlayOfferSelection.selectFounderAnnual(candidates);
        final details = selected.sourceProductDetails;
        if (details is ProductDetails) return details.price;
      } else if (productId == PlayProductIds.monthly) {
        final selected = PlayOfferSelection.selectMonthlyTrial(candidates);
        final details = selected.sourceProductDetails;
        if (details is ProductDetails) return details.price;
      }
    } on PlayBillingConfigurationException {
      // Fallback abajo.
    }
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
    KlooviBillingDiag.log('load_products_start', {
      'had_products': _products.isNotEmpty,
      'count': _products.length,
    });
    final loadSw = Stopwatch()..start();
    _phase = PlayBillingPhase.loadingProducts;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();

    try {
      KlooviBillingDiag.log('billing_available_start', {'scope': 'load_products'});
      final availableSw = Stopwatch()..start();
      final available = await _store.isAvailable();
      KlooviBillingDiag.log('billing_available_result', {
        'scope': 'load_products',
        'available': available,
        'elapsed_ms': availableSw.elapsedMilliseconds,
      });
      if (!available) {
        _products = const [];
        _phase = PlayBillingPhase.unavailable;
        _lastErrorCode = 'store_unavailable';
        _lastErrorMessage = 'Google Play Billing no está disponible.';
        onChanged?.call();
        KlooviBillingDiag.log('load_products_result', {
          'ok': false,
          'reason': 'store_unavailable',
          'elapsed_ms': loadSw.elapsedMilliseconds,
        });
        return;
      }

      KlooviBillingDiag.log('product_query_start', {
        'requested': PlayProductIds.all.join(','),
      });
      final querySw = Stopwatch()..start();
      final response = await _store.queryProductDetails(PlayProductIds.all);
      final foundIds = response.productDetails.map((p) => p.id).toList();
      KlooviBillingDiag.log('product_query_result', {
        'elapsed_ms': querySw.elapsedMilliseconds,
        'found_count': foundIds.length,
        'found_ids': foundIds.join(','),
        'not_found': response.notFoundIDs.join(','),
        'has_error': response.error != null,
        'error_code': response.error?.code ?? '',
      });
      if (response.error != null) {
        _products = const [];
        _phase = PlayBillingPhase.purchaseError;
        _lastErrorCode = response.error!.code;
        _lastErrorMessage = response.error!.message;
        onChanged?.call();
        KlooviBillingDiag.log('load_products_result', {
          'ok': false,
          'reason': 'query_error',
          'elapsed_ms': loadSw.elapsedMilliseconds,
        });
        return;
      }

      _products = List<ProductDetails>.from(response.productDetails);
      if (response.notFoundIDs.isNotEmpty || _products.isEmpty) {
        _phase = PlayBillingPhase.configurationError;
        _lastErrorCode = 'products_not_found';
        _lastErrorMessage =
            'Productos no encontrados: ${response.notFoundIDs.join(', ')}';
        onChanged?.call();
        KlooviBillingDiag.log('load_products_result', {
          'ok': false,
          'reason': 'products_not_found',
          'elapsed_ms': loadSw.elapsedMilliseconds,
          'found_count': _products.length,
        });
        return;
      }

      _phase = PlayBillingPhase.productsLoaded;
      onChanged?.call();
      KlooviBillingDiag.log('load_products_result', {
        'ok': true,
        'elapsed_ms': loadSw.elapsedMilliseconds,
        'found_count': _products.length,
        'found_ids': _products.map((p) => p.id).join(','),
      });
    } catch (e) {
      _products = const [];
      _setError('load_products_failed', e.toString(), onChanged);
      KlooviBillingDiag.log('load_products_result', {
        'ok': false,
        'reason': 'exception',
        'error': KlooviBillingDiag.sanitizeError(e),
        'elapsed_ms': loadSw.elapsedMilliseconds,
      });
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
    KlooviBillingDiag.log('billing_available', {'available': available});
    if (!available) {
      _setPhase(
        PlayBillingPhase.unavailable,
        code: 'store_unavailable',
        message: 'Google Play Billing no está disponible.',
        onChanged: onChanged,
      );
      return;
    }

    final session = ++_restoreSession;
    _phase = PlayBillingPhase.restorePending;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();

    KlooviBillingDiag.log('restore_call_start', {
      'stream_subscribed': _purchaseSub != null,
      'initialized': _initialized,
    });
    final restoreSw = Stopwatch()..start();
    try {
      await _store.restorePurchases();
      if (session != _restoreSession) return;
      KlooviBillingDiag.log('restore_call_completed', {
        'elapsed_ms': restoreSw.elapsedMilliseconds,
      });
    } catch (e) {
      if (session != _restoreSession) return;
      KlooviBillingDiag.log('restore_call_error', {
        'error': KlooviBillingDiag.sanitizeError(e),
        'elapsed_ms': restoreSw.elapsedMilliseconds,
      });
      _setError('restore_failed', e.toString(), onChanged);
      return;
    }

    if (session != _restoreSession) return;

    // El Future de Play puede completar antes de que el stream emita.
    // Si ya avanzamos (restored/validating/error), no tocar la fase.
    if (_phase != PlayBillingPhase.restorePending) return;

    if (restoreEventGrace > Duration.zero) {
      await Future<void>.delayed(restoreEventGrace);
    }
    if (session != _restoreSession) return;
    if (_phase != PlayBillingPhase.restorePending) return;

    // Sin eventos: liberar UI. No afirma que no exista compra en Play.
    KlooviBillingDiag.log('restore_timeout', {
      'duration_ms': restoreEventGrace.inMilliseconds,
      'reason': 'restore_no_updates',
    });
    _setPhase(
      _products.isNotEmpty
          ? PlayBillingPhase.productsLoaded
          : PlayBillingPhase.idle,
      code: 'restore_no_updates',
      message: 'restore_no_updates',
      onChanged: onChanged,
    );
  }

  /// Expone candidatos desde productos cargados (también útil en tests).
  List<PlayOfferCandidate> offerCandidatesFrom(List<ProductDetails> products) {
    final out = <PlayOfferCandidate>[];
    for (final details in products) {
      if (details is! GooglePlayProductDetails) continue;
      final index = details.subscriptionIndex;
      final offers = details.productDetails.subscriptionOfferDetails;
      if (index == null ||
          offers == null ||
          index < 0 ||
          index >= offers.length) {
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
    KlooviBillingDiag.log('purchase_selected_enter', {
      'cached_products': _products.length,
      'phase': _phase.name,
    });

    KlooviBillingDiag.log('billing_available_start', {
      'scope': 'purchase_selected',
    });
    final availableSw = Stopwatch()..start();
    final bool available;
    try {
      available = await _store.isAvailable();
    } catch (e) {
      KlooviBillingDiag.log('billing_available_result', {
        'scope': 'purchase_selected',
        'available': false,
        'elapsed_ms': availableSw.elapsedMilliseconds,
        'error': KlooviBillingDiag.sanitizeError(e),
      });
      KlooviBillingDiag.log('purchase_preflight_abort', {
        'reason': 'is_available_exception',
        'error': KlooviBillingDiag.sanitizeError(e),
      });
      _setError('buy_failed', e.toString(), onChanged);
      return;
    }
    KlooviBillingDiag.log('billing_available_result', {
      'scope': 'purchase_selected',
      'available': available,
      'elapsed_ms': availableSw.elapsedMilliseconds,
    });
    if (!available) {
      _setPhase(
        PlayBillingPhase.unavailable,
        code: 'store_unavailable',
        message: 'Google Play Billing no está disponible.',
        onChanged: onChanged,
      );
      KlooviBillingDiag.log('purchase_preflight_abort', {
        'reason': 'store_unavailable',
      });
      return;
    }

    if (_products.isEmpty) {
      KlooviBillingDiag.log('purchase_preflight', {
        'step': 'load_products_needed',
      });
      await loadProducts(onChanged: onChanged);
    } else {
      KlooviBillingDiag.log('purchase_preflight', {
        'step': 'using_cached_products',
        'count': _products.length,
        'ids': _products.map((p) => p.id).join(','),
      });
      // Un configurationError previo (p.ej. offer selection) no debe atrapar
      // el CTA: con catálogo en caché se reintenta la selección.
      if (_phase == PlayBillingPhase.configurationError ||
          _phase == PlayBillingPhase.purchaseError) {
        KlooviBillingDiag.log('purchase_preflight', {
          'step': 'clear_stale_phase_for_retry',
          'from_phase': _phase.name,
          'error_code': _lastErrorCode ?? '',
        });
        _phase = PlayBillingPhase.productsLoaded;
        _lastErrorCode = null;
        _lastErrorMessage = null;
        onChanged?.call();
      }
    }
    if (_phase == PlayBillingPhase.unavailable) {
      KlooviBillingDiag.log('purchase_preflight_abort', {
        'reason': 'phase_after_load',
        'phase': _phase.name,
        'error_code': _lastErrorCode ?? '',
      });
      return;
    }
    if (_products.isEmpty) {
      KlooviBillingDiag.log('purchase_preflight_abort', {
        'reason': 'no_products',
        'phase': _phase.name,
        'error_code': _lastErrorCode ?? '',
      });
      return;
    }

    final candidates = offerCandidatesFrom(_products);
    KlooviBillingDiag.log('offer_selection_start', {
      'cached_products': _products.length,
      'candidate_count': candidates.length,
      'candidate_ids': candidates
          .map((c) => '${c.productId}/${c.basePlanId}/${c.offerId ?? 'none'}')
          .join(';'),
    });

    late final PlayOfferCandidate selected;
    try {
      selected = select(candidates);
    } on PlayBillingConfigurationException catch (e) {
      KlooviBillingDiag.log('offer_selection_result', {
        'ok': false,
        'code': e.code,
      });
      _setPhase(
        PlayBillingPhase.configurationError,
        code: e.code,
        message: e.message,
        onChanged: onChanged,
      );
      KlooviBillingDiag.log('purchase_preflight_abort', {
        'reason': 'offer_selection_failed',
        'code': e.code,
      });
      return;
    }

    KlooviBillingDiag.log('offer_selection_result', {
      'ok': true,
      'product': selected.productId,
      'base_plan': selected.basePlanId,
      'offer': selected.offerId ?? 'none',
    });

    final productDetails = selected.sourceProductDetails;
    KlooviBillingDiag.log('product_details_type_check', {
      'ok': productDetails is GooglePlayProductDetails,
      'type': productDetails?.runtimeType.toString() ?? 'null',
    });
    if (productDetails is! GooglePlayProductDetails) {
      _setPhase(
        PlayBillingPhase.configurationError,
        code: 'invalid_product_details',
        message: 'La oferta seleccionada no es GooglePlayProductDetails.',
        onChanged: onChanged,
      );
      KlooviBillingDiag.log('purchase_preflight_abort', {
        'reason': 'invalid_product_details',
      });
      return;
    }

    _phase = PlayBillingPhase.purchasePending;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();

    KlooviBillingDiag.log('buy_launch', {
      'product': selected.productId,
      'base_plan': selected.basePlanId,
      'offer': selected.offerId ?? 'none',
    });

    try {
      final ok = await _store.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: productDetails,
          offerToken: selected.offerToken,
        ),
      );
      if (!ok) {
        KlooviBillingDiag.log('buy_result', {'result': 'rejected'});
        _setError(
          'buy_non_consumable_rejected',
          'Google Play rechazó iniciar la compra.',
          onChanged,
        );
      } else {
        KlooviBillingDiag.log('buy_result', {'result': 'accepted'});
      }
    } catch (e) {
      KlooviBillingDiag.log('buy_result', {
        'result': 'error',
        'error': KlooviBillingDiag.sanitizeError(e),
      });
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

  void _onPurchases(List<PurchaseDetails> purchases, VoidCallback? onChanged) {
    KlooviBillingDiag.log('purchase_stream_event', {'count': purchases.length});
    for (final purchase in purchases) {
      KlooviBillingDiag.log('purchase_status', {
        'status': purchase.status.name,
        'product': purchase.productID,
      });
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
          // NO completePurchase aquí. NO otorgar Pro.
          final payload = PlayPurchasePayload.fromPurchaseDetails(purchase);
          if (payload == null) {
            KlooviBillingDiag.log('missing_purchase_token', {
              'status': purchase.status.name,
              'product': purchase.productID,
            });
            _setError(
              'missing_purchase_token',
              'La compra no incluye purchase_token.',
              onChanged,
            );
            continue;
          }
          _lastPendingValidation = payload;
          _lastPendingDetails = purchase;
          debugPrint(
            'PlayBillingClient: ${purchase.status.name} needs validation '
            'product=${payload.productId} '
            'pendingComplete=${payload.pendingCompletePurchase}',
          );
          _phase = purchase.status == PurchaseStatus.restored
              ? PlayBillingPhase.restoreNeedsValidation
              : PlayBillingPhase.purchaseNeedsValidation;
          onChanged?.call();
          if (purchase.pendingCompletePurchase) {
            debugPrint(
              'PlayBillingClient: deferring completePurchase until backend '
              'validation succeeds.',
            );
          }
          unawaited(_runValidationIfNeeded(payload, purchase, onChanged));
      }
    }
  }

  Future<void> _runValidationIfNeeded(
    PlayPurchasePayload payload,
    PurchaseDetails details,
    VoidCallback? onChanged,
  ) async {
    final handler = _validationHandler;
    if (handler == null) {
      KlooviBillingDiag.log('validation_skip', {'reason': 'no_handler'});
      return;
    }
    if (_validationInFlight) {
      KlooviBillingDiag.log('validation_skip', {'reason': 'in_flight'});
      return;
    }

    final session = ++_validationSession;
    _validationInFlight = true;
    _phase = PlayBillingPhase.validating;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    onChanged?.call();
    KlooviBillingDiag.log('validation_start', {
      'product': payload.productId,
      'status': details.status.name,
    });

    final future = handler(payload, details);
    try {
      final ok = await future.timeout(validationTimeout);
      if (session != _validationSession) return;
      _applyValidationOutcome(ok, onChanged);
    } on TimeoutException {
      if (session != _validationSession) return;
      _phase = PlayBillingPhase.validationFailed;
      _lastErrorCode = 'validation_timeout';
      _lastErrorMessage = 'validation_timeout';
      onChanged?.call();
      // La validación sigue en curso; si termina OK después, actualizar UI.
      unawaited(
        future
            .then((ok) {
              if (session != _validationSession) return;
              if (ok) {
                _applyValidationOutcome(true, onChanged);
              }
            })
            .catchError((Object e, StackTrace st) {
              debugPrint('PlayBillingClient late validation error: $e\n$st');
            }),
      );
    } catch (e, st) {
      debugPrint('PlayBillingClient validation handler error: $e\n$st');
      if (session != _validationSession) return;
      _setError('validation_handler_error', e.toString(), onChanged);
    } finally {
      if (session == _validationSession) {
        _validationInFlight = false;
      }
    }
  }

  void _applyValidationOutcome(bool ok, VoidCallback? onChanged) {
    if (ok) {
      _phase = PlayBillingPhase.validationSucceeded;
      _lastErrorCode = null;
      _lastErrorMessage = null;
    } else {
      _phase = PlayBillingPhase.validationFailed;
      _lastErrorCode ??= 'validation_failed';
      _lastErrorMessage ??= 'La validación de la compra falló.';
    }
    onChanged?.call();
  }

  /// Completa/ack la compra en Play Billing Library tras validación OK.
  Future<void> completePurchase(PurchaseDetails details) async {
    completePurchaseCallCount++;
    await _store.completePurchase(details);
  }

  @visibleForTesting
  Future<void> completePurchaseForTests(PurchaseDetails details) =>
      completePurchase(details);

  /// Publica error de validación backend sin mutar la fase (la pone el handler).
  void reportValidationFailure(String code, String message) {
    _lastErrorCode = code;
    _lastErrorMessage = message;
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
