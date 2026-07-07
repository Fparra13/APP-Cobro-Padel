import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';

/// Selector compacto de idioma (onboarding y ajustes).
class MatchPayLocalePicker extends StatelessWidget {
  const MatchPayLocalePicker({super.key});

  static String _label(MatchPayStrings l10n, Locale locale) => switch (
        locale.languageCode) {
    'es' => l10n.tr('langEs'),
    'en' => l10n.tr('langEn'),
    'pt' => l10n.tr('langPt'),
    _ => locale.languageCode,
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final l10n = MatchPayStrings.of(settings.locale);
    final selected = AppSettingsController.normalizePickerLocale(settings.locale);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: AppSettingsController.pickerLocales.map((locale) {
        final isSelected = locale.languageCode == selected.languageCode;
        return ChoiceChip(
          label: Text(_label(l10n, locale)),
          selected: isSelected,
          onSelected: (_) => settings.setLocale(locale),
          selectedColor: MatchPayTokens.accentSuccessBg,
          side: BorderSide(
            color: isSelected
                ? MatchPayTokens.accentSuccess
                : MatchPayTokens.borderSubtle,
          ),
          labelStyle: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? MatchPayTokens.accentSuccess
                : MatchPayTokens.inkMuted,
          ),
        );
      }).toList(),
    );
  }
}
