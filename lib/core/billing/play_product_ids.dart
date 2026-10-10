/// Product IDs y base plans / offers de Google Play (Kloovi Pro V1).
abstract final class PlayProductIds {
  PlayProductIds._();

  static const monthly = 'kloovi_pro_monthly';
  static const founderAnnual = 'kloovi_pro_founder_annual';

  static const monthlyBasePlan = 'monthly';
  static const monthlyTrialOffer = 'trial-14d';

  /// Base plan anual correcto (renovación anual) en Play Console.
  static const founderBasePlan = 'founder-annual-v2';

  /// Plan legacy mal configurado como mensual; no se usa para comprar.
  /// El backend aún lo acepta al revalidar compras antiguas.
  static const founderBasePlanLegacy = 'annual';

  static const Set<String> all = {monthly, founderAnnual};
}
