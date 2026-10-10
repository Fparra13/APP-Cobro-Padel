import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:matchpay/core/billing/billing_entitlement.dart';
import 'package:matchpay/core/billing/play_billing_client.dart';
import 'package:matchpay/core/billing/play_billing_diag.dart';
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
  int buyCalls = 0;
  bool available = true;
  Duration isAvailableDelay = Duration.zero;
  List<ProductDetails> queryProducts = const [];
  List<String> notFoundIds = const [];
  IAPError? queryError;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async {
    if (isAvailableDelay > Duration.zero) {
      await Future<void>.delayed(isAvailableDelay);
    }
    return available;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: queryProducts,
      notFoundIDs: notFoundIds.isNotEmpty
          ? notFoundIds
          : (queryProducts.isEmpty ? identifiers.toList() : <String>[]),
      error: queryError,
    );
  }

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls++;
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

  @override
  Future<PlayPurchaseValidationResult> validate(
    PlayPurchasePayload payload,
  ) async {
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
  String token = 'server-token-should-never-appear-in-diag',
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
  details.pendingCompletePurchase = true;
  return details;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<({String phase, Map<String, Object?> fields})> captured;

  setUp(() {
    captured = [];
    KlooviBillingDiag.sinkForTests = (phase, fields) {
      captured.add((phase: phase, fields: fields));
    };
  });

  tearDown(() {
    KlooviBillingDiag.sinkForTests = null;
  });

  test('sanitizeError no incluye mensaje con token', () {
    final err = Exception('token=supersecret.jwt.value.here');
    expect(KlooviBillingDiag.sanitizeError(err), '_Exception');
  });

  test('log omite claves prohibidas y no expone token en fields', () {
    KlooviBillingDiag.log('purchase_status', {
      'status': 'restored',
      'product': PlayProductIds.monthly,
      'purchase_token': 'SHOULD_NOT_APPEAR',
      'token': 'ALSO_NO',
    });
    expect(captured, hasLength(1));
    expect(captured.single.phase, 'purchase_status');
    expect(captured.single.fields.containsKey('purchase_token'), isFalse);
    expect(captured.single.fields.containsKey('token'), isFalse);
    expect(captured.single.fields['product'], PlayProductIds.monthly);
    expect(captured.single.fields['status'], 'restored');
  });

  test('restore sin eventos emite restore_timeout sin conceder Pro', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _FakeStore();
    final validator = _FakeValidator();
    final client = PlayBillingClient(
      store: store,
      restoreEventGrace: const Duration(milliseconds: 20),
      validationTimeout: const Duration(seconds: 30),
    );
    final sub = SubscriptionService.forTesting(
      playBilling: client,
      validator: validator,
    );
    await client.initialize(onChanged: sub.notifyListeners);

    await sub.restorePurchases();

    final phases = captured.map((e) => e.phase).toList();
    expect(phases, contains('billing_available'));
    expect(phases, contains('restore_call_start'));
    expect(phases, contains('restore_call_completed'));
    expect(phases, contains('restore_timeout'));
    expect(phases, isNot(contains('validation_start')));
    expect(sub.isPro, isFalse);
    expect(sub.playBillingPhase, isNot(PlayBillingPhase.restorePending));

    final timeout = captured.firstWhere((e) => e.phase == 'restore_timeout');
    expect(timeout.fields['reason'], 'restore_no_updates');
    expect(timeout.fields['duration_ms'], 20);

    await client.dispose();
    await store.close();
  });

  test(
    'restored emite purchase_status y validation_start; late OK sigue',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _FakeStore();
      final validator = _FakeValidator();
      validator.nextValidate = PlayPurchaseValidationResult.success(
        entitlement: BillingEntitlement(
          isPro: true,
          source: 'subscription',
          status: 'trial',
          productId: PlayProductIds.monthly,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
          isTrial: true,
          isFounder: false,
          autoRenewing: true,
          lastVerifiedAt: DateTime.now().toUtc(),
        ),
        acknowledged: true,
        acknowledgePending: false,
      );
      final client = PlayBillingClient(
        store: store,
        restoreEventGrace: const Duration(milliseconds: 40),
        validationTimeout: const Duration(seconds: 30),
      );
      final sub = SubscriptionService.forTesting(
        playBilling: client,
        validator: validator,
      );
      await client.initialize(onChanged: sub.notifyListeners);

      final restoreFuture = sub.restorePurchases();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      store.emit([_purchase(status: PurchaseStatus.restored)]);
      await restoreFuture;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final phases = captured.map((e) => e.phase).toList();
      expect(phases, contains('purchase_stream_event'));
      expect(phases, contains('purchase_status'));
      expect(phases, contains('validation_start'));
      expect(phases, contains('entitlement_result'));
      expect(phases, isNot(contains('restore_timeout')));

      final status = captured.firstWhere((e) => e.phase == 'purchase_status');
      expect(status.fields['status'], 'restored');
      expect(status.fields['product'], PlayProductIds.monthly);
      expect(
        status.fields.values.map((v) => '$v').join(' '),
        isNot(contains('server-token')),
      );

      final entitlement = captured.lastWhere(
        (e) => e.phase == 'entitlement_result',
      );
      expect(entitlement.fields['is_pro'], isTrue);
      expect(sub.isPro, isTrue);

      await client.dispose();
      await store.close();
    },
  );

  test('purchase_tap solo expone plan monthly|founder', () {
    KlooviBillingDiag.log('purchase_tap', {'plan': 'monthly'});
    KlooviBillingDiag.log('purchase_tap', {'plan': 'founder'});
    expect(captured.map((e) => e.phase), everyElement('purchase_tap'));
    expect(captured[0].fields['plan'], 'monthly');
    expect(captured[1].fields['plan'], 'founder');
    expect(
      captured.expand((e) => e.fields.keys),
      isNot(contains('purchase_token')),
    );
  });

  test('buy_launch no incluye offerToken ni purchase_token', () {
    KlooviBillingDiag.log('buy_launch', {
      'product': PlayProductIds.monthly,
      'base_plan': 'monthly',
      'offer': 'trial-14d',
      'offerToken': 'SHOULD_NOT_APPEAR',
      'purchase_token': 'ALSO_NO',
    });
    final launch = captured.single;
    expect(launch.phase, 'buy_launch');
    expect(launch.fields['product'], PlayProductIds.monthly);
    expect(launch.fields['base_plan'], 'monthly');
    expect(launch.fields['offer'], 'trial-14d');
    expect(launch.fields.containsKey('offerToken'), isFalse);
    expect(launch.fields.containsKey('purchase_token'), isFalse);
  });

  test('missing_purchase_token emite diag sin token', () {
    final client = PlayBillingClient(store: _FakeStore());
    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.purchased, token: ''),
    ]);
    final miss = captured.where((e) => e.phase == 'missing_purchase_token');
    expect(miss, isNotEmpty);
    expect(miss.first.fields['status'], 'purchased');
    expect(miss.first.fields['product'], PlayProductIds.monthly);
    expect(
      miss.first.fields.values.map((v) => '$v').join(' '),
      isNot(contains('server-token')),
    );
    expect(client.phase, PlayBillingPhase.purchaseError);
    expect(client.lastErrorCode, 'missing_purchase_token');
  });

  test('validation_skip reason=no_handler', () {
    final client = PlayBillingClient(store: _FakeStore());
    // Sin validationHandler.
    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.purchased),
    ]);
    final skips = captured.where((e) => e.phase == 'validation_skip').toList();
    expect(skips, isNotEmpty);
    expect(skips.first.fields['reason'], 'no_handler');
    expect(captured.map((e) => e.phase), isNot(contains('validation_start')));
  });

  test('validation_skip reason=in_flight', () async {
    final store = _FakeStore();
    final client = PlayBillingClient(
      store: store,
      validationTimeout: const Duration(seconds: 30),
    );
    final gate = Completer<bool>();
    client.validationHandler = (payload, details) => gate.future;

    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.purchased, token: 'tok-a'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(captured.map((e) => e.phase), contains('validation_start'));

    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.purchased, token: 'tok-b'),
    ]);
    final skips = captured
        .where(
          (e) =>
              e.phase == 'validation_skip' && e.fields['reason'] == 'in_flight',
        )
        .toList();
    expect(skips, isNotEmpty);

    gate.complete(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await client.dispose();
    await store.close();
  });

  test('preflight: store unavailable aborta antes de buy_launch', () async {
    final store = _FakeStore()..available = false;
    final client = PlayBillingClient(store: store);
    await client.purchaseMonthlyTrial();

    final phases = captured.map((e) => e.phase).toList();
    expect(phases, contains('purchase_selected_enter'));
    expect(phases, contains('billing_available_start'));
    expect(phases, contains('billing_available_result'));
    expect(phases, contains('purchase_preflight_abort'));
    expect(phases, isNot(contains('buy_launch')));
    expect(store.buyCalls, 0);

    final abort = captured.firstWhere(
      (e) => e.phase == 'purchase_preflight_abort',
    );
    expect(abort.fields['reason'], 'store_unavailable');
    final avail = captured.firstWhere(
      (e) =>
          e.phase == 'billing_available_result' &&
          e.fields['scope'] == 'purchase_selected',
    );
    expect(avail.fields['available'], isFalse);
    expect(avail.fields.containsKey('elapsed_ms'), isTrue);

    await client.dispose();
    await store.close();
  });

  test('preflight: products_not_found aborta sin buy_launch', () async {
    final store = _FakeStore()
      ..queryProducts = const []
      ..notFoundIds = [PlayProductIds.monthly, PlayProductIds.founderAnnual];
    final client = PlayBillingClient(store: store);
    await client.purchaseMonthlyTrial();

    final phases = captured.map((e) => e.phase).toList();
    expect(phases, contains('load_products_start'));
    expect(phases, contains('product_query_start'));
    expect(phases, contains('product_query_result'));
    expect(phases, contains('load_products_result'));
    expect(phases, contains('purchase_preflight_abort'));
    expect(phases, isNot(contains('buy_launch')));
    expect(store.buyCalls, 0);

    final query = captured.firstWhere((e) => e.phase == 'product_query_result');
    expect(query.fields['found_count'], 0);
    expect(
      '${query.fields['found_ids']}${query.fields['not_found']}',
      isNot(contains('token')),
    );

    final abort = captured.lastWhere(
      (e) => e.phase == 'purchase_preflight_abort',
    );
    expect(abort.fields['reason'], 'no_products');
    expect(abort.fields['phase'], 'configurationError');

    await client.dispose();
    await store.close();
  });

  test('preflight: sin candidatos Google aborta en offer_selection', () async {
    final store = _FakeStore()
      ..queryProducts = [
        ProductDetails(
          id: PlayProductIds.monthly,
          title: 'Monthly',
          description: 'd',
          price: r'$1',
          rawPrice: 1,
          currencyCode: 'CLP',
        ),
      ]
      ..notFoundIds = const [];
    final client = PlayBillingClient(store: store);
    await client.purchaseMonthlyTrial();

    final phases = captured.map((e) => e.phase).toList();
    expect(phases, contains('offer_selection_start'));
    expect(phases, contains('offer_selection_result'));
    expect(phases, contains('purchase_preflight_abort'));
    expect(phases, isNot(contains('buy_launch')));

    final sel = captured.firstWhere(
      (e) => e.phase == 'offer_selection_result',
    );
    expect(sel.fields['ok'], isFalse);
    expect(sel.fields['code'], 'missing_monthly_purchasable_offer');

    final abort = captured.lastWhere(
      (e) => e.phase == 'purchase_preflight_abort',
    );
    expect(abort.fields['reason'], 'offer_selection_failed');
    expect(client.phase, PlayBillingPhase.configurationError);

    await client.dispose();
    await store.close();
  });

  test('reintento tras configurationError limpia fase y reintenta selección',
      () async {
    final store = _FakeStore()
      ..queryProducts = [
        ProductDetails(
          id: PlayProductIds.monthly,
          title: 'Monthly',
          description: 'd',
          price: r'$1',
          rawPrice: 1,
          currencyCode: 'CLP',
        ),
      ]
      ..notFoundIds = const [];
    final client = PlayBillingClient(store: store);

    await client.purchaseMonthlyTrial();
    expect(client.phase, PlayBillingPhase.configurationError);
    expect(client.lastErrorCode, 'missing_monthly_purchasable_offer');

    captured.clear();
    await client.purchaseMonthlyTrial();

    final phases = captured.map((e) => e.phase).toList();
    expect(
      phases,
      contains('purchase_preflight'),
    );
    final clear = captured.firstWhere(
      (e) =>
          e.phase == 'purchase_preflight' &&
          e.fields['step'] == 'clear_stale_phase_for_retry',
    );
    expect(clear.fields['from_phase'], 'configurationError');
    expect(phases, contains('offer_selection_start'));
    expect(
      captured.where(
        (e) =>
            e.phase == 'purchase_preflight_abort' &&
            e.fields['reason'] == 'phase_after_load',
      ),
      isEmpty,
    );
    // Sigue sin buy_launch (productos fake no son GooglePlay), pero recuperable.
    expect(phases, contains('offer_selection_result'));
    expect(client.phase, PlayBillingPhase.configurationError);

    await client.dispose();
    await store.close();
  });

  test('purchase_tap_skipped reason=busy (guard concurrente)', () {
    // Réplica del guard síncrono de PaywallSheet._onPrimaryCta.
    var busy = false;
    void onPrimaryCta() {
      if (busy) {
        KlooviBillingDiag.log('purchase_tap_skipped', {'reason': 'busy'});
        return;
      }
      busy = true;
      KlooviBillingDiag.log('purchase_tap', {'plan': 'monthly'});
    }

    onPrimaryCta();
    onPrimaryCta();
    expect(
      captured.where((e) => e.phase == 'purchase_tap'),
      hasLength(1),
    );
    expect(
      captured.where((e) => e.phase == 'purchase_tap_skipped'),
      hasLength(1),
    );
    expect(captured.last.fields['reason'], 'busy');
  });

  test('sanitizedValidationDiagCode cubre códigos seguros', () {
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.notAuthenticated,
        ),
      ),
      'not_authenticated',
    );
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.networkError,
        ),
      ),
      'network_error',
    );
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.unauthorized,
          httpStatus: 401,
        ),
      ),
      'http_401',
    );
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.conflict,
          httpStatus: 409,
        ),
      ),
      'http_409',
    );
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.googlePlayFailed,
          httpStatus: 502,
        ),
      ),
      'http_502',
    );
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.failure(
          errorCode: PlayPurchaseValidationErrorCode.serverError,
          httpStatus: 503,
        ),
      ),
      'http_5xx',
    );
    expect(
      sanitizedValidationDiagCode(
        PlayPurchaseValidationResult.success(
          entitlement: BillingEntitlement(
            isPro: true,
            source: 'subscription',
            status: 'trial',
            productId: PlayProductIds.monthly,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
            isTrial: true,
            isFounder: false,
            autoRenewing: true,
            lastVerifiedAt: DateTime.now().toUtc(),
          ),
          acknowledged: true,
          acknowledgePending: false,
        ),
      ),
      isNull,
    );
  });
}
