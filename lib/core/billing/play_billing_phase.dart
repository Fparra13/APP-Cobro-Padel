/// Fase del cliente Google Play Billing (no es entitlement Pro).
enum PlayBillingPhase {
  idle,
  loadingProducts,
  productsLoaded,
  purchasePending,
  purchaseNeedsValidation,
  validating,
  validationSucceeded,
  validationFailed,
  purchaseError,
  restorePending,
  restoreNeedsValidation,
  unavailable,
  configurationError,
}
