import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:matchpay/core/billing/play_purchase_payload.dart';

PurchaseDetails _details({
  required String productId,
  required String token,
  String? purchaseId,
  PurchaseStatus status = PurchaseStatus.purchased,
  bool pendingComplete = true,
}) {
  final details = PurchaseDetails(
    purchaseID: purchaseId,
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '{"mock":true}',
      serverVerificationData: token,
      source: 'google_play',
    ),
    transactionDate: '1710000000000',
    status: status,
  );
  details.pendingCompletePurchase = pendingComplete;
  return details;
}

void main() {
  test('extrae product_id, purchase_token y purchaseID', () {
    final payload = PlayPurchasePayload.fromPurchaseDetails(
      _details(
        productId: 'kloovi_pro_monthly',
        token: 'play-token-abc',
        purchaseId: 'GPA.1234',
      ),
    );

    expect(payload, isNotNull);
    expect(payload!.productId, 'kloovi_pro_monthly');
    expect(payload.purchaseToken, 'play-token-abc');
    expect(payload.purchaseId, 'GPA.1234');
    expect(payload.toValidationRequestBody(), {
      'purchase_token': 'play-token-abc',
      'product_id': 'kloovi_pro_monthly',
    });
  });

  test('token vacío → null', () {
    expect(
      PlayPurchasePayload.fromPurchaseDetails(
        _details(productId: 'kloovi_pro_monthly', token: '   '),
      ),
      isNull,
    );
  });

  test('restored conserva status y pendingComplete', () {
    final payload = PlayPurchasePayload.fromPurchaseDetails(
      _details(
        productId: 'kloovi_pro_founder_annual',
        token: 'tok',
        status: PurchaseStatus.restored,
        pendingComplete: true,
      ),
    );
    expect(payload!.status, PurchaseStatus.restored);
    expect(payload.pendingCompletePurchase, isTrue);
  });
}
