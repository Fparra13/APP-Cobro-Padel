import 'package:in_app_purchase/in_app_purchase.dart';

/// Datos extraídos de una compra Play listos para futura validación backend.
class PlayPurchasePayload {
  final String productId;
  final String purchaseToken;
  final String? purchaseId;
  final String? transactionDate;
  final PurchaseStatus status;
  final bool pendingCompletePurchase;

  const PlayPurchasePayload({
    required this.productId,
    required this.purchaseToken,
    required this.purchaseId,
    required this.transactionDate,
    required this.status,
    required this.pendingCompletePurchase,
  });

  /// Android: `serverVerificationData` es el purchaseToken.
  static PlayPurchasePayload? fromPurchaseDetails(PurchaseDetails details) {
    final token = details.verificationData.serverVerificationData.trim();
    if (token.isEmpty) return null;
    final productId = details.productID.trim();
    if (productId.isEmpty) return null;

    return PlayPurchasePayload(
      productId: productId,
      purchaseToken: token,
      purchaseId: details.purchaseID,
      transactionDate: details.transactionDate,
      status: details.status,
      pendingCompletePurchase: details.pendingCompletePurchase,
    );
  }

  Map<String, String> toValidationRequestBody() => {
        'purchase_token': purchaseToken,
        'product_id': productId,
      };
}
