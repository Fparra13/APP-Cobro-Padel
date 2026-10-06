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
    test('monthly + trial-14d → seleccionado', () {
      final selected = PlayOfferSelection.selectMonthlyTrial([
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

    test('monthly + otra offer → rechazado', () {
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
            'missing_monthly_trial_offer',
          ),
        ),
      );
    });

    test('monthly sin trial-14d → rechazado', () {
      expect(
        () => PlayOfferSelection.selectMonthlyTrial([
          _offer(
            productId: PlayProductIds.monthly,
            basePlanId: PlayProductIds.monthlyBasePlan,
            offerId: null,
          ),
        ]),
        throwsA(isA<PlayBillingConfigurationException>()),
      );
    });
  });

  group('PlayOfferSelection.founder', () {
    test('founder annual base plan → seleccionado', () {
      final selected = PlayOfferSelection.selectFounderAnnual([
        _offer(
          productId: PlayProductIds.founderAnnual,
          basePlanId: PlayProductIds.founderBasePlan,
          offerId: null,
          offerToken: 'founder-token',
        ),
      ]);
      expect(selected.offerToken, 'founder-token');
      expect(selected.offerId, isNull);
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
