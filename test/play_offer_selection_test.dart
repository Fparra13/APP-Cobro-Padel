import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/billing/play_offer_selection.dart';
import 'package:matchpay/core/billing/play_product_ids.dart';

PlayOfferCandidate _offer({
  required String productId,
  required String basePlanId,
  String? offerId,
  String offerToken = 'token',
  bool freeTrial = false,
  bool intro = false,
}) {
  return PlayOfferCandidate(
    productId: productId,
    basePlanId: basePlanId,
    offerId: offerId,
    offerToken: offerToken,
    hasFreeTrialPhase: freeTrial,
    hasIntroductoryPricePhase: intro,
  );
}

void main() {
  group('PlayOfferSelection.monthly', () {
    test('monthly + trial-14d → seleccionado (prioridad sobre base)', () {
      final selected = PlayOfferSelection.selectMonthlyTrial([
        _offer(
          productId: PlayProductIds.monthly,
          basePlanId: PlayProductIds.monthlyBasePlan,
          offerId: null,
          offerToken: 'monthly-base-token',
        ),
        _offer(
          productId: PlayProductIds.monthly,
          basePlanId: 'other',
          offerId: PlayProductIds.monthlyTrialOffer,
        ),
        _offer(
          productId: PlayProductIds.monthly,
          basePlanId: PlayProductIds.monthlyBasePlan,
          offerId: PlayProductIds.monthlyTrialOffer,
          offerToken: 'monthly-trial-token',
        ),
      ]);
      expect(selected.offerToken, 'monthly-trial-token');
      expect(selected.offerId, PlayProductIds.monthlyTrialOffer);
    });

    test('sin trial, base monthly con token → selecciona base', () {
      final selected = PlayOfferSelection.selectMonthlyTrial([
        _offer(
          productId: PlayProductIds.monthly,
          basePlanId: PlayProductIds.monthlyBasePlan,
          offerId: null,
          offerToken: 'monthly-base-token',
        ),
        _offer(
          productId: PlayProductIds.monthly,
          basePlanId: PlayProductIds.monthlyBasePlan,
          offerId: 'promo-7d',
          offerToken: 'promo-token',
        ),
      ]);
      expect(selected.offerId, isNull);
      expect(selected.basePlanId, PlayProductIds.monthlyBasePlan);
      expect(selected.offerToken, 'monthly-base-token');
    });

    test('solo promo / sin trial ni base → rechazado recuperable', () {
      expect(
        () => PlayOfferSelection.selectMonthlyTrial([
          _offer(
            productId: PlayProductIds.monthly,
            basePlanId: PlayProductIds.monthlyBasePlan,
            offerId: 'promo-7d',
          ),
        ]),
        throwsA(
          isA<PlayBillingConfigurationException>().having(
            (e) => e.code,
            'code',
            'missing_monthly_purchasable_offer',
          ),
        ),
      );
    });

    test('base monthly sin token → rechazado', () {
      expect(
        () => PlayOfferSelection.selectMonthlyTrial([
          _offer(
            productId: PlayProductIds.monthly,
            basePlanId: PlayProductIds.monthlyBasePlan,
            offerId: null,
            offerToken: '   ',
          ),
        ]),
        throwsA(
          isA<PlayBillingConfigurationException>().having(
            (e) => e.code,
            'code',
            'missing_monthly_purchasable_offer',
          ),
        ),
      );
    });
  });

  group('PlayOfferSelection.founder', () {
    test('founder-annual-v2 → seleccionado; legacy annual ignorado', () {
      final selected = PlayOfferSelection.selectFounderAnnual([
        _offer(
          productId: PlayProductIds.founderAnnual,
          basePlanId: PlayProductIds.founderBasePlanLegacy,
          offerId: null,
          offerToken: 'legacy-monthly-misconfigured',
        ),
        _offer(
          productId: PlayProductIds.founderAnnual,
          basePlanId: PlayProductIds.founderBasePlan,
          offerId: null,
          offerToken: 'founder-v2-token',
        ),
      ]);
      expect(selected.offerToken, 'founder-v2-token');
      expect(selected.basePlanId, 'founder-annual-v2');
      expect(selected.offerId, isNull);
    });

    test('solo legacy annual → rechazado (no comprar plan incorrecto)', () {
      expect(
        () => PlayOfferSelection.selectFounderAnnual([
          _offer(
            productId: PlayProductIds.founderAnnual,
            basePlanId: PlayProductIds.founderBasePlanLegacy,
            offerId: null,
          ),
        ]),
        throwsA(
          isA<PlayBillingConfigurationException>().having(
            (e) => e.code,
            'code',
            'missing_founder_annual_base_plan',
          ),
        ),
      );
    });

    test('founder con trial → rechazado', () {
      expect(
        () => PlayOfferSelection.selectFounderAnnual([
          _offer(
            productId: PlayProductIds.founderAnnual,
            basePlanId: PlayProductIds.founderBasePlan,
            offerId: null,
            freeTrial: true,
          ),
        ]),
        throwsA(isA<PlayBillingConfigurationException>()),
      );
    });

    test('founder con intro → rechazado', () {
      expect(
        () => PlayOfferSelection.selectFounderAnnual([
          _offer(
            productId: PlayProductIds.founderAnnual,
            basePlanId: PlayProductIds.founderBasePlan,
            offerId: null,
            intro: true,
          ),
        ]),
        throwsA(isA<PlayBillingConfigurationException>()),
      );
    });

    test('producto desconocido → rechazado', () {
      expect(
        () => PlayOfferSelection.selectFounderAnnual([
          _offer(
            productId: 'unknown_product',
            basePlanId: PlayProductIds.founderBasePlan,
            offerId: null,
          ),
        ]),
        throwsA(isA<PlayBillingConfigurationException>()),
      );
    });
  });
}
