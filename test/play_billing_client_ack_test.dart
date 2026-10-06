import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:matchpay/core/billing/play_billing_client.dart';
import 'package:matchpay/core/billing/play_billing_phase.dart';

class _FakeStore implements PlayBillingStore {
  final _controller = StreamController<List<PurchaseDetails>>.broadcast();
  int completeCalls = 0;

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
  Future<void> restorePurchases() async {}

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return false;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeCalls++;
  }

  Future<void> close() => _controller.close();
}

PurchaseDetails _purchase({
  required PurchaseStatus status,
  bool pendingComplete = true,
}) {
  final details = PurchaseDetails(
    purchaseID: 'GPA.1',
    productID: 'kloovi_pro_monthly',
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: 'server-token-1',
      source: 'google_play',
    ),
    transactionDate: '1',
    status: status,
  );
  details.pendingCompletePurchase = pendingComplete;
  return details;
}

void main() {
  test('purchased/restored/pending/error/canceled sin completePurchase',
      () async {
    final fake = _FakeStore();
    final client = PlayBillingClient(store: fake);

    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.purchased, pendingComplete: true),
    ]);
    expect(client.phase, PlayBillingPhase.purchaseNeedsValidation);
    expect(client.lastPendingValidation?.purchaseToken, 'server-token-1');
    expect(client.lastPendingValidation?.pendingCompletePurchase, isTrue);
    expect(fake.completeCalls, 0);
    expect(client.completePurchaseCallCount, 0);

    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.restored),
    ]);
    expect(client.phase, PlayBillingPhase.restoreNeedsValidation);
    expect(fake.completeCalls, 0);

    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.pending),
    ]);
    expect(client.phase, PlayBillingPhase.purchasePending);
    expect(fake.completeCalls, 0);

    client.handlePurchasesForTest([
      _purchase(status: PurchaseStatus.canceled),
    ]);
    expect(client.phase, PlayBillingPhase.idle);
    expect(fake.completeCalls, 0);

    final errored = _purchase(status: PurchaseStatus.error);
    errored.error = IAPError(
      source: 'google_play',
      code: 'test',
      message: 'boom',
    );
    client.handlePurchasesForTest([errored]);
    expect(client.phase, PlayBillingPhase.purchaseError);
    expect(fake.completeCalls, 0);

    await fake.close();
  });
}
