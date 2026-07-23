/// Catálogo de ofertas del paywall Kloovi Pro.
///
/// Hoy usa precios estáticos formateados. En la etapa de Play Billing se
/// rellenará [formattedPrice] (y opcionalmente [formattedOriginalPrice])
/// desde `ProductDetails.price` sin cambiar la UI.
enum PaywallPlanId {
  monthly,
  yearly,
}

class PaywallPlanOffer {
  final PaywallPlanId id;

  /// Precio visible (alineado con `ProductDetails.price` en Billing).
  final String formattedPrice;

  /// Precio anterior tachado (promos futuras). Null = no mostrar.
  final String? formattedOriginalPrice;

  /// Reservado para Product ID de Play; null hasta la etapa Billing.
  final String? storeProductId;

  final bool isRecommended;
  final bool showFounderBadge;

  const PaywallPlanOffer({
    required this.id,
    required this.formattedPrice,
    this.formattedOriginalPrice,
    this.storeProductId,
    this.isRecommended = false,
    this.showFounderBadge = false,
  });

  PaywallPlanOffer copyWith({
    PaywallPlanId? id,
    String? formattedPrice,
    String? formattedOriginalPrice,
    bool clearFormattedOriginalPrice = false,
    String? storeProductId,
    bool clearStoreProductId = false,
    bool? isRecommended,
    bool? showFounderBadge,
  }) {
    return PaywallPlanOffer(
      id: id ?? this.id,
      formattedPrice: formattedPrice ?? this.formattedPrice,
      formattedOriginalPrice: clearFormattedOriginalPrice
          ? null
          : (formattedOriginalPrice ?? this.formattedOriginalPrice),
      storeProductId: clearStoreProductId
          ? null
          : (storeProductId ?? this.storeProductId),
      isRecommended: isRecommended ?? this.isRecommended,
      showFounderBadge: showFounderBadge ?? this.showFounderBadge,
    );
  }
}

abstract final class PaywallCatalog {
  PaywallCatalog._();

  static const List<PaywallPlanOffer> offers = [
    PaywallPlanOffer(
      id: PaywallPlanId.yearly,
      formattedPrice: r'$14.990',
      isRecommended: true,
      showFounderBadge: true,
    ),
    PaywallPlanOffer(
      id: PaywallPlanId.monthly,
      formattedPrice: r'$2.990',
    ),
  ];

  static PaywallPlanOffer offerFor(PaywallPlanId id) =>
      offers.firstWhere((o) => o.id == id);
}
