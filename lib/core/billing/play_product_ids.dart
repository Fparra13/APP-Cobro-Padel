/// Product IDs y base plans / offers de Google Play (Kloovi Pro V1).
abstract final class PlayProductIds {
  PlayProductIds._();

  static const monthly = 'kloovi_pro_monthly';
  static const founderAnnual = 'kloovi_pro_founder_annual';

  static const monthlyBasePlan = 'monthly';
  static const monthlyTrialOffer = 'trial-14d';

  static const founderBasePlan = 'annual';

  static const Set<String> all = {monthly, founderAnnual};
}
