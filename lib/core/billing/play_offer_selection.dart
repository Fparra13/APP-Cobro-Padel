import 'play_product_ids.dart';

/// Candidato de oferta Play (DTO testeable sin Billing Client).
class PlayOfferCandidate {
  final String productId;
  final String basePlanId;
  final String? offerId;
  final String offerToken;
  final bool hasFreeTrialPhase;
  final bool hasIntroductoryPricePhase;

  /// Referencia opaca al [ProductDetails] / [GooglePlayProductDetails] origen.
  final Object? sourceProductDetails;

  const PlayOfferCandidate({
    required this.productId,
    required this.basePlanId,
    required this.offerId,
    required this.offerToken,
    required this.hasFreeTrialPhase,
    required this.hasIntroductoryPricePhase,
    this.sourceProductDetails,
  });
}

/// Error de configuración de catálogo Play (sin fallback silencioso).
class PlayBillingConfigurationException implements Exception {
  final String code;
  final String message;

  const PlayBillingConfigurationException(this.code, this.message);

  @override
  String toString() => 'PlayBillingConfigurationException($code): $message';
}

/// Selección estricta de offers Kloovi V1.
abstract final class PlayOfferSelection {
  PlayOfferSelection._();

  /// Monthly: prefiere `monthly` + `trial-14d` si Play lo expone.
  ///
  /// Si el trial no es elegible, usa el base plan `monthly` (`offerId == null`)
  /// solo cuando Google Play devolvió un offer token utilizable.
  static PlayOfferCandidate selectMonthlyTrial(
    Iterable<PlayOfferCandidate> candidates,
  ) {
    final trialMatches = candidates.where((c) {
      return c.productId == PlayProductIds.monthly &&
          c.basePlanId == PlayProductIds.monthlyBasePlan &&
          c.offerId == PlayProductIds.monthlyTrialOffer &&
          c.offerToken.trim().isNotEmpty;
    }).toList(growable: false);

    if (trialMatches.length > 1) {
      throw const PlayBillingConfigurationException(
        'ambiguous_monthly_trial_offer',
        'Hay múltiples offers trial-14d para kloovi_pro_monthly/monthly.',
      );
    }
    if (trialMatches.length == 1) {
      return trialMatches.single;
    }

    // Base plan: offerId null (Play) + token de esa oferta concreta.
    final baseMatches = candidates.where((c) {
      return c.productId == PlayProductIds.monthly &&
          c.basePlanId == PlayProductIds.monthlyBasePlan &&
          c.offerId == null &&
          c.offerToken.trim().isNotEmpty;
    }).toList(growable: false);

    if (baseMatches.length > 1) {
      throw const PlayBillingConfigurationException(
        'ambiguous_monthly_base_plan',
        'Hay múltiples base plans monthly válidos para kloovi_pro_monthly.',
      );
    }
    if (baseMatches.length == 1) {
      return baseMatches.single;
    }

    throw const PlayBillingConfigurationException(
      'missing_monthly_purchasable_offer',
      'No hay oferta mensual comprable (trial-14d ni base monthly) '
          'para kloovi_pro_monthly.',
    );
  }

  /// Founder: base plan `founder-annual-v2` sin trial/intro offer.
  ///
  /// No selecciona el plan legacy `annual` (mal configurado en Play).
  static PlayOfferCandidate selectFounderAnnual(
    Iterable<PlayOfferCandidate> candidates,
  ) {
    final matches = candidates.where((c) {
      return c.productId == PlayProductIds.founderAnnual &&
          c.basePlanId == PlayProductIds.founderBasePlan &&
          c.offerId == null &&
          !c.hasFreeTrialPhase &&
          !c.hasIntroductoryPricePhase &&
          c.offerToken.trim().isNotEmpty;
    }).toList(growable: false);

    if (matches.isEmpty) {
      throw const PlayBillingConfigurationException(
        'missing_founder_annual_base_plan',
        'No existe base plan founder-annual-v2 válido (sin trial/intro) '
            'para kloovi_pro_founder_annual.',
      );
    }
    if (matches.length > 1) {
      throw const PlayBillingConfigurationException(
        'ambiguous_founder_annual_base_plan',
        'Hay múltiples base plans founder-annual-v2 válidos para '
            'kloovi_pro_founder_annual.',
      );
    }
    return matches.single;
  }
}
