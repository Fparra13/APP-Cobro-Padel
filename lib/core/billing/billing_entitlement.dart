/// Entitlement comercial oficial (RPC `get_my_billing_entitlement`).
class BillingEntitlement {
  final bool isPro;
  final String source;
  final String? status;
  final String? productId;
  final DateTime? expiresAt;
  final bool isTrial;
  final bool isFounder;
  final bool? autoRenewing;
  final DateTime? lastVerifiedAt;

  const BillingEntitlement({
    required this.isPro,
    required this.source,
    required this.status,
    required this.productId,
    required this.expiresAt,
    required this.isTrial,
    required this.isFounder,
    required this.autoRenewing,
    required this.lastVerifiedAt,
  });

  static const none = BillingEntitlement(
    isPro: false,
    source: 'none',
    status: null,
    productId: null,
    expiresAt: null,
    isTrial: false,
    isFounder: false,
    autoRenewing: null,
    lastVerifiedAt: null,
  );

  factory BillingEntitlement.fromJson(Map<String, dynamic> json) {
    return BillingEntitlement(
      isPro: json['is_pro'] == true,
      source: (json['source'] as String?)?.trim().isNotEmpty == true
          ? (json['source'] as String).trim()
          : 'none',
      status: json['status'] as String?,
      productId: json['product_id'] as String?,
      expiresAt: _parseTime(json['expires_at']),
      isTrial: json['is_trial'] == true,
      isFounder: json['is_founder'] == true,
      autoRenewing: json['auto_renewing'] as bool?,
      lastVerifiedAt: _parseTime(json['last_verified_at']),
    );
  }

  /// Pro comercial vigente ahora (respeta `expires_at` aunque `isPro` esté obsoleto).
  ///
  /// No usa SharedPreferences. Staff/admin se evalúa fuera de este método.
  bool grantsCommercialProNow([DateTime? now]) {
    if (!isPro) return false;
    final expiry = expiresAt;
    if (expiry == null) return true;
    final clock = now ?? DateTime.now().toUtc();
    return expiry.toUtc().isAfter(clock);
  }

  static DateTime? _parseTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }
}
