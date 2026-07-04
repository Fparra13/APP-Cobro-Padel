import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import 'translation_maps.dart';
import 'payment_concept_l10n.dart';

/// Localización MatchPay — delega en [TranslationMaps].
class MatchPayStrings {
  final String _languageCode;

  const MatchPayStrings(this._languageCode);

  String tr(String key, {Map<String, String> params = const {}}) =>
      TranslationMaps.lookup(_languageCode, key, params: params);

  /// Traduce un concepto guardado en BD al idioma activo.
  String translateConcept(String stored) =>
      PaymentConceptL10n.translate(stored, _languageCode);

  String get appName => tr('appName');
  String get settingsTitle => tr('settingsTitle');
  String get sportLabel => tr('sportLabel');
  String get languageLabel => tr('languageLabel');
  String get currencyLabel => tr('currencyLabel');
  String get loading => tr('loading');
  String get save => tr('save');
  String get cancel => tr('cancel');
  String get confirm => tr('confirm');
  String get close => tr('close');
  String get retry => tr('retry');
  String get signOut => tr('signOut');
  String get understood => tr('understood');
  String get continueBtn => tr('continueBtn');
  String get yesDelete => tr('yesDelete');
  String get no => tr('no');
  String get test => tr('test');
  String get permissions => tr('permissions');
  String get helpTooltip => tr('helpTooltip');
  String get refreshTooltip => tr('refreshTooltip');
  String get navHome => tr('navHome');
  String get navPlayers => tr('navPlayers');
  String get navHistory => tr('navHistory');
  String get navCloud => tr('navCloud');
  String get navConfig => tr('navConfig');
  String get navMyCobros => tr('navMyCobros');
  String get homeAdminTitle => tr('homeAdminTitle');
  String get configScreenTitle => tr('configScreenTitle');
  String get sharedExpensesTitle => tr('groupExpensesTitle');
  String get sharedExpensesSubtitle => tr('groupExpensesSubtitle');
  String get addExpense => tr('addExpense');
  String get expenseLabelHint => tr('expenseLabelHint');
  String get facilityLabel => tr('venueLabel');
  String get ballsLabel => tr('ballsLabel');
  String get groupExpensesTitle => tr('groupExpensesTitle');
  String get groupExpensesSubtitle => tr('groupExpensesSubtitle');
  String get paywallTitle => tr('paywallTitle');
  String get paywallCta => tr('paywallCta');
  String get paywallSubtitle => tr('paywallSubtitle');
  String get paywallRestore => tr('paywallRestore');
  String get paywallFreeTitle => tr('paywallFreeTitle');
  String get paywallProTitle => tr('paywallProTitle');
  String get freeFeatureDebts => tr('freeFeatureDebts');
  String get freeFeatureReceipts => tr('freeFeatureReceipts');
  String get proFeatureCreate => tr('proFeatureCreate');
  String get proFeatureAutomate => tr('proFeatureAutomate');
  String get proFeatureStats => tr('proFeatureStats');
  String get sportOnboardingTitle => tr('sportOnboardingTitle');
  String get sportOnboardingSubtitle => tr('sportOnboardingSubtitle');
  String get sportOnboardingContinue => tr('sportOnboardingContinue');
  String get sportDescPadel => tr('sportDescPadel');
  String get sportDescFootball => tr('sportDescFootball');
  String get sportDescTennis => tr('sportDescTennis');
  String get sportDescGeneral => tr('sportDescGeneral');

  static MatchPayStrings of(Locale locale) =>
      MatchPayStrings(locale.languageCode);
}

extension MatchPayL10n on BuildContext {
  MatchPayStrings get l10n => MatchPayStrings.of(
        Provider.of<AppSettingsController>(this, listen: false).locale,
      );

  String tr(String key, {Map<String, String> params = const {}}) =>
      l10n.tr(key, params: params);
}
