import 'dart:async';
import 'dart:io';

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
  BillingEntitlement nextEntitlement = BillingEntitlement.none;
  PlayPurchasePayload? lastPayload;
  int validateCalls = 0;
  int fetchCalls = 0;
  Object? validateThrow;

  @override
  Future<PlayPurchaseValidationResult> validate(
    PlayPurchasePayload payload,
  ) async {
    validateCalls++;
    lastPayload = payload;
    if (validateThrow != null) throw validateThrow!;
    return nextValidate ??
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.unknown,
        );
  }

  @override
  Future<BillingEntitlement> fetchEntitlement() async {
    fetchCalls++;
    return nextEntitlement;
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

BillingEntitlement _proEntitlement({String productId = PlayProductIds.monthly}) {
  return BillingEntitlement(
    isPro: true,
    source: 'subscription',
    status: 'trial',
    productId: productId,
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 14)),
    isTrial: productId == PlayProductIds.monthly,
    isFounder: productId == PlayProductIds.founderAnnual,
    autoRenewing: true,
    lastVerifiedAt: DateTime.now().toUtc(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayPurchasePayload', () {
    test('monthly payload correcto', () {
      final payload = PlayPurchasePayload.fromPurchaseDetails(
        _purchase(
          status: PurchaseStatus.purchased,
          productId: PlayProductIds.monthly,
          token: 'tok-monthly',
        ),
      );
      expect(payload, isNotNull);
      expect(
        payload!.toValidationRequestBody(),
        {
          'purchase_token': 'tok-monthly',
          'product_id': PlayProductIds.monthly,
        },
      );
    });

    test('Founder payload correcto', () {
      final payload = PlayPurchasePayload.fromPurchaseDetails(
        _purchase(
          status: PurchaseStatus.purchased,
          productId: PlayProductIds.founderAnnual,
          token: 'tok-founder',
        ),
      );
      expect(payload, isNotNull);
      expect(
        payload!.toValidationRequestBody(),
        {
          'purchase_token': 'tok-founder',
          'product_id': PlayProductIds.founderAnnual,
        },
      );
    });

    test('token extraído de serverVerificationData', () {
      final payload = PlayPurchasePayload.fromPurchaseDetails(
        _purchase(status: PurchaseStatus.purchased, token: '  abc  '),
      );
      expect(payload!.purchaseToken, 'abc');
    });
  });

  group('SubscriptionService + validator', () {
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
        validationTimeout: const Duration(seconds: 30),
      );
      sub = SubscriptionService.forTesting(
        playBilling: client,
        validator: validator,
      );
      // Asegura wiring del validationHandler vía getter.
      expect(sub.playBillingPhase, isNotNull);
      await client.initialize(onChanged: () {});
    });

    tearDown(() async {
      await client.dispose();
      await store.close();
    });

    test('backend 200 + is_pro=true → Pro + completePurchase', () async {
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: _proEntitlement(),
        acknowledged: true,
        acknowledgePending: false,
      );

      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(validator.validateCalls, 1);
      expect(validator.lastPayload?.purchaseToken, 'server-token-1');
      expect(sub.isPro, isTrue);
      expect(sub.entitlement.isPro, isTrue);
      expect(store.completeCalls, 1);
      expect(client.completePurchaseCallCount, 1);
      expect(client.phase, PlayBillingPhase.validationSucceeded);
    });

    test('backend 200 + is_pro=false → no Pro, no completePurchase', () async {
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: BillingEntitlement.none,
        acknowledged: false,
        acknowledgePending: false,
      );

      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sub.isPro, isFalse);
      expect(store.completeCalls, 0);
      expect(client.phase, PlayBillingPhase.validationFailed);
      expect(
        sub.lastValidationResult?.errorCode,
        PlayPurchaseValidationErrorCode.notPro,
      );
    });

    test('backend 401', () async {
      validator.nextValidate = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.unauthorized,
        httpStatus: 401,
      );
      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sub.isPro, isFalse);
      expect(store.completeCalls, 0);
      expect(
        sub.lastValidationResult?.errorCode,
        PlayPurchaseValidationErrorCode.unauthorized,
      );
    });

    test('backend 409', () async {
      validator.nextValidate = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.conflict,
        httpStatus: 409,
        safeMessage: 'token_bound_to_other_user',
      );
      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(store.completeCalls, 0);
      expect(
        sub.lastValidationResult?.safeMessage,
        'token_bound_to_other_user',
      );
    });

    test('backend 500/502', () async {
      validator.nextValidate = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.googlePlayFailed,
        httpStatus: 502,
      );
      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(store.completeCalls, 0);
      expect(
        sub.lastValidationResult?.errorCode,
        PlayPurchaseValidationErrorCode.googlePlayFailed,
      );

      validator.nextValidate = PlayPurchaseValidationResult.failure(
        errorCode: PlayPurchaseValidationErrorCode.serverError,
        httpStatus: 500,
      );
      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased, token: 'tok-2'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        sub.lastValidationResult?.errorCode,
        PlayPurchaseValidationErrorCode.serverError,
      );
    });

    test('error de red en validate', () async {
      validator.validateThrow = Exception('socket');
      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Handler catch → validation_handler_error phase purchaseError
      expect(sub.isPro, isFalse);
      expect(store.completeCalls, 0);
    });

    test('restore → validation', () async {
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: _proEntitlement(),
        acknowledged: true,
        acknowledgePending: false,
      );
      final restoreFuture = sub.restorePurchases();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(store.restoreCalled, isTrue);

      client.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.restored),
      ]);
      await restoreFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(validator.validateCalls, 1);
      expect(sub.isPro, isTrue);
      expect(store.completeCalls, 1);
    });

    test('no completePurchase antes de validación', () async {
      final completer = Completer<PlayPurchaseValidationResult>();
      validator.nextValidate = null;
      // Override validate via throw path: use delayed by replacing nextValidate
      // after delay — inject custom validator behavior:
      final delayed = _DelayedValidator(completer);
      final delayedStore = _FakeStore();
      final delayedClient = PlayBillingClient(store: delayedStore);
      final delayedSub = SubscriptionService.forTesting(
        playBilling: delayedClient,
        validator: delayed,
      );
      expect(delayedSub.playBillingPhase, isNotNull);
      await delayedClient.initialize(onChanged: () {});

      delayedClient.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(delayedStore.completeCalls, 0);
      expect(delayedSub.isPro, isFalse);

      completer.complete(
        PlayPurchaseValidationResult.success(
          entitlement: _proEntitlement(),
          acknowledged: true,
          acknowledgePending: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delayedStore.completeCalls, 1);
      expect(delayedSub.isPro, isTrue);
      await delayedClient.dispose();
      await delayedStore.close();
    });

    test('Founder product_id en payload de validación', () async {
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: _proEntitlement(productId: PlayProductIds.founderAnnual),
        acknowledged: true,
        acknowledgePending: false,
      );
      client.handlePurchasesForTest([
        _purchase(
          status: PurchaseStatus.purchased,
          productId: PlayProductIds.founderAnnual,
          token: 'founder-tok',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(validator.lastPayload?.productId, PlayProductIds.founderAnnual);
      expect(sub.entitlement.isFounder, isTrue);
    });

    test('acceso_ilimitado sigue siendo bypass; email founder no otorga Pro',
        () {
      sub.syncFromProfile(
        accesoIlimitado: false,
        email: 'fparram13@gmail.com',
      );
      expect(sub.hasUnlimitedAccess, isFalse);
      expect(sub.isPro, isFalse);

      sub.syncFromProfile(
        accesoIlimitado: true,
        email: 'staff@example.com',
      );
      expect(sub.hasUnlimitedAccess, isTrue);
      expect(sub.isPro, isTrue);
      expect(sub.can(ProFeature.createMatch), isTrue);
    });

    test('setProActive(true) no concede Pro', () async {
      sub.syncFromProfile(accesoIlimitado: false, email: 'a@b.com');
      // ignore: deprecated_member_use_from_same_package
      await sub.setProActive(true);
      expect(sub.isPro, isFalse);
      expect(sub.can(ProFeature.createMatch), isFalse);
    });
  });

  group('Organizer vs Pro contracts', () {
    test('crear encuentro requiere Pro', () async {
      SharedPreferences.setMockInitialValues({});
      final sub = SubscriptionService.instance;
      sub.clearProfileEntitlements();
      await sub.clearCommercialEntitlement();
      sub.syncFromProfile(accesoIlimitado: false, email: 'x@y.com');
      expect(sub.can(ProFeature.createMatch), isFalse);

      sub.syncFromProfile(accesoIlimitado: true, email: 'staff@y.com');
      expect(sub.can(ProFeature.createMatch), isTrue);
    });

    test('organizer flow source no abre paywall/requirePro', () {
      final source = File('lib/utils/organizer_subscription_flow.dart')
          .readAsStringSync();
      expect(source.contains('requirePro'), isFalse);
      expect(source.contains('showPaywallSheet'), isFalse);
      expect(source.contains('becomeOrganizer()'), isTrue);
    });
  });
}

class _DelayedValidator implements PlayPurchaseValidator {
  _DelayedValidator(this._completer);

  final Completer<PlayPurchaseValidationResult> _completer;

  @override
  Future<PlayPurchaseValidationResult> validate(
    PlayPurchasePayload payload,
  ) =>
      _completer.future;

  @override
  Future<BillingEntitlement> fetchEntitlement() async =>
      BillingEntitlement.none;
}
