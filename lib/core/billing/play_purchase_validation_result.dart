import 'billing_entitlement.dart';

enum PlayPurchaseValidationErrorCode {
  notAuthenticated,
  missingToken,
  unexpectedProduct,
  unauthorized,
  conflict,
  googlePlayFailed,
  serverError,
  networkError,
  notPro,
  unknown,
}

/// Resultado de `validate-play-purchase` (+ entitlement opcional).
class PlayPurchaseValidationResult {
  final bool ok;
  final bool acknowledged;
  final bool acknowledgePending;
  final BillingEntitlement? entitlement;
  final PlayPurchaseValidationErrorCode? errorCode;
  final int? httpStatus;
  final String? safeMessage;

  const PlayPurchaseValidationResult._({
    required this.ok,
    required this.acknowledged,
    required this.acknowledgePending,
    required this.entitlement,
    required this.errorCode,
    required this.httpStatus,
    required this.safeMessage,
  });

  factory PlayPurchaseValidationResult.success({
    required BillingEntitlement entitlement,
    required bool acknowledged,
    required bool acknowledgePending,
  }) {
    final grants = entitlement.isPro;
    return PlayPurchaseValidationResult._(
      ok: grants,
      acknowledged: acknowledged,
      acknowledgePending: acknowledgePending,
      entitlement: entitlement,
      errorCode: grants ? null : PlayPurchaseValidationErrorCode.notPro,
      httpStatus: 200,
      safeMessage: grants ? null : 'purchase_not_pro',
    );
  }

  factory PlayPurchaseValidationResult.failure({
    required PlayPurchaseValidationErrorCode errorCode,
    int? httpStatus,
    String? safeMessage,
  }) {
    return PlayPurchaseValidationResult._(
      ok: false,
      acknowledged: false,
      acknowledgePending: false,
      entitlement: null,
      errorCode: errorCode,
      httpStatus: httpStatus,
      safeMessage: safeMessage ?? errorCode.name,
    );
  }

  bool get shouldCompletePurchase => ok;
}
