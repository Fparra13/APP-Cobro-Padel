import 'billing/play_product_ids.dart';

/// Catálogo de ofertas del paywall Kloovi Pro.
///
/// Precios estáticos son fallback visual. Si Play devolvió [ProductDetails],
/// la UI puede mostrar el precio de tienda sin convertirlo en autoridad
/// comercial (el contrato comercial sigue siendo Play Console + backend).
enum PaywallPlanId {
  monthly,
  yearly,
}

class PaywallPlanOffer {
  final PaywallPlanId id;

  /// Precio visible fallback (si Play no devolvió producto).
  final String formattedPrice;

  /// Precio anterior tachado (promos futuras). Null = no mostrar.
  final String? formattedOriginalPrice;

  /// Product ID de Google Play.
  final String storeProductId;

  final bool isRecommended;
  final bool showFounderBadge;

  const PaywallPlanOffer({
    required this.id,
    required this.formattedPrice,
    this.formattedOriginalPrice,
    required this.storeProductId,
    this.isRecommended = false,
    this.showFounderBadge = false,
  });

  PaywallPlanOffer copyWith({
    PaywallPlanId? id,
    String? formattedPrice,
    String? formattedOriginalPrice,
    bool clearFormattedOriginalPrice = false,
    String? storeProductId,
    bool? isRecommended,
    bool? showFounderBadge,
  }) {
    return PaywallPlanOffer(
      id: id ?? this.id,
      formattedPrice: formattedPrice ?? this.formattedPrice,
      formattedOriginalPrice: clearFormattedOriginalPrice
          ? null
          : (formattedOriginalPrice ?? this.formattedOriginalPrice),
      storeProductId: storeProductId ?? this.storeProductId,
      isRecommended: isRecommended ?? this.isRecommended,
      showFounderBadge: showFounderBadge ?? this.showFounderBadge,
    );
  }
}

abstract final class PaywallCatalog {
  PaywallCatalog._();

  static const List<PaywallPlanOffer> offers = [
    PaywallPlanOffer(
      id: PaywallPlanId.monthly,
      formattedPrice: r'$2.990',
      storeProductId: PlayProductIds.monthly,
      isRecommended: true,
    ),
    PaywallPlanOffer(
      id: PaywallPlanId.yearly,
      formattedPrice: r'$14.990',
      storeProductId: PlayProductIds.founderAnnual,
      showFounderBadge: true,
    ),
  ];

  static PaywallPlanOffer offerFor(PaywallPlanId id) =>
      offers.firstWhere((o) => o.id == id);
}
