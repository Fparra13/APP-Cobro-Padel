import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:matchpay/core/billing/billing_entitlement.dart';
import 'package:matchpay/core/billing/play_billing_client.dart';
import 'package:matchpay/core/billing/play_billing_phase.dart';
import 'package:matchpay/core/billing/play_product_ids.dart';
import 'package:matchpay/core/billing/play_purchase_payload.dart';
import 'package:matchpay/core/billing/play_purchase_validation_result.dart';
import 'package:matchpay/core/billing/play_purchase_validator.dart';
import 'package:matchpay/core/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStore implements PlayBillingStore {
  final _controller = StreamController<List<PurchaseDetails>>.broadcast();
  int completeCalls = 0;
  bool restoreCalled = false;
  Duration restoreDelay = Duration.zero;
  List<PurchaseDetails>? emitAfterRestore;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: const [],
      notFoundIDs: identifiers.toList(),
    );
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalled = true;
    if (restoreDelay > Duration.zero) {
      await Future<void>.delayed(restoreDelay);
    }
    final pending = emitAfterRestore;
    if (pending != null) {
      // Emite en el siguiente microtask (simula stream tras el Future).
      scheduleMicrotask(() => _controller.add(pending));
    }
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeCalls++;
  }

  void emit(List<PurchaseDetails> purchases) => _controller.add(purchases);

  Future<void> close() => _controller.close();
}

class _FakeValidator implements PlayPurchaseValidator {
  PlayPurchaseValidationResult? nextValidate;
  Completer<PlayPurchaseValidationResult>? delayedValidate;
  PlayPurchasePayload? lastPayload;
  int validateCalls = 0;

  @override
  Future<PlayPurchaseValidationResult> validate(
    PlayPurchasePayload payload,
  ) async {
    validateCalls++;
    lastPayload = payload;
    if (delayedValidate != null) {
      return delayedValidate!.future;
    }
    return nextValidate ??
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.unknown,
        );
  }

  @override
  Future<BillingEntitlement> fetchEntitlement() async {
    return BillingEntitlement.none;
  }
}

PurchaseDetails _purchase({
  required PurchaseStatus status,
  String productId = PlayProductIds.monthly,
  String token = 'server-token-1',
  bool pendingComplete = true,
}) {
  final details = PurchaseDetails(
    purchaseID: 'GPA.1',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: token,
      source: 'google_play',
    ),
    transactionDate: '1',
    status: status,
  );
  details.pendingCompletePurchase = pendingComplete;
  return details;
}

BillingEntitlement _proEntitlement() {
  return BillingEntitlement(
    isPro: true,
    source: 'subscription',
    status: 'trial',
    productId: PlayProductIds.monthly,
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 14)),
    isTrial: true,
    isFounder: false,
    autoRenewing: true,
    lastVerifiedAt: DateTime.now().toUtc(),
  );
}

/// true si la UI del paywall trataría la fase como carga (ctaBusy sin _busy).
bool _purchaseInFlight(PlayBillingPhase phase) {
  return phase == PlayBillingPhase.purchasePending ||
      phase == PlayBillingPhase.restorePending ||
      phase == PlayBillingPhase.loadingProducts ||
      phase == PlayBillingPhase.validating ||
      phase == PlayBillingPhase.purchaseNeedsValidation ||
      phase == PlayBillingPhase.restoreNeedsValidation;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStore store;
  late _FakeValidator validator;
  late PlayBillingClient client;
  late SubscriptionService sub;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _FakeStore();
    validator = _FakeValidator();
    client = PlayBillingClient(
      store: store,
      restoreEventGrace: const Duration(milliseconds: 40),
      validationTimeout: const Duration(milliseconds: 80),
    );
    sub = SubscriptionService.forTesting(
      playBilling: client,
      validator: validator,
    );
    await client.initialize(onChanged: sub.notifyListeners);
  });

  tearDown(() async {
    await client.dispose();
    await store.close();
  });

  group('restore UI state', () {
    test('restore sin eventos abandona restorePending sin conceder Pro',
        () async {
      await sub.restorePurchases();

      expect(store.restoreCalled, isTrue);
      expect(sub.playBillingPhase, isNot(PlayBillingPhase.restorePending));
      expect(sub.playBillingErrorCode, 'restore_no_updates');
      expect(_purchaseInFlight(sub.playBillingPhase), isFalse);
      expect(sub.isPro, isFalse);
      expect(validator.validateCalls, 0);
      expect(store.completeCalls, 0);
    });

    test('restored + validación exitosa concede Pro solo con entitlement',
        () async {
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: _proEntitlement(),
        acknowledged: true,
        acknowledgePending: false,
      );

      final restoreFuture = sub.restorePurchases();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      store.emit([_purchase(status: PurchaseStatus.restored)]);
      await restoreFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(validator.validateCalls, 1);
      expect(sub.isPro, isTrue);
      expect(sub.playBillingPhase, PlayBillingPhase.validationSucceeded);
      expect(store.completeCalls, 1);
      expect(sub.playBillingErrorCode, isNot('restore_no_updates'));
    });

    test('restored + validación fallida no concede Pro y libera carga',
        () async {
      validator.nextValidate = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.unauthorized,
        safeMessage: 'unauthorized',
      );

      final restoreFuture = sub.restorePurchases();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      store.emit([_purchase(status: PurchaseStatus.restored)]);
      await restoreFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(validator.validateCalls, 1);
      expect(sub.isPro, isFalse);
      expect(sub.playBillingPhase, PlayBillingPhase.validationFailed);
      expect(_purchaseInFlight(sub.playBillingPhase), isFalse);
      expect(store.completeCalls, 0);
    });

    test('validación que no responde a tiempo libera UI sin Pro', () async {
      validator.delayedValidate = Completer<PlayPurchaseValidationResult>();

      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.restored),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(sub.playBillingPhase, PlayBillingPhase.validationFailed);
      expect(sub.playBillingErrorCode, 'validation_timeout');
      expect(_purchaseInFlight(sub.playBillingPhase), isFalse);
      expect(sub.isPro, isFalse);
      expect(store.completeCalls, 0);
    });

    test('evento tardío tras settle de restore aún puede validar', () async {
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: _proEntitlement(),
        acknowledged: true,
        acknowledgePending: false,
      );

      await sub.restorePurchases();
      expect(sub.playBillingErrorCode, 'restore_no_updates');
      expect(sub.isPro, isFalse);

      store.emit([_purchase(status: PurchaseStatus.restored)]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(validator.validateCalls, 1);
      expect(sub.isPro, isTrue);
      expect(sub.playBillingPhase, PlayBillingPhase.validationSucceeded);
      expect(store.completeCalls, 1);
    });

    test('timeout luego resultado tardío OK actualiza Pro sin complete falso',
        () async {
      final completer = Completer<PlayPurchaseValidationResult>();
      validator.delayedValidate = completer;

      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.restored),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sub.playBillingErrorCode, 'validation_timeout');
      expect(sub.isPro, isFalse);

      completer.complete(
        PlayPurchaseValidationResult.success(
          entitlement: _proEntitlement(),
          acknowledged: true,
          acknowledgePending: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(sub.isPro, isTrue);
      expect(sub.playBillingPhase, PlayBillingPhase.validationSucceeded);
      expect(store.completeCalls, 1);
    });

    test('ningún camino de restore vacío concede Pro', () async {
      await sub.restorePurchases();
      expect(sub.isPro, isFalse);

      validator.nextValidate = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.notPro,
        safeMessage: 'purchase_not_pro',
      );
      store.emit([_purchase(status: PurchaseStatus.restored)]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sub.isPro, isFalse);
      expect(store.completeCalls, 0);
    });
  });
}
