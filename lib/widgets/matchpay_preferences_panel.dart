import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/country_sport_catalog.dart';
import '../core/currency_config.dart';
import '../l10n/matchpay_strings.dart';
import '../services/notification_service.dart';
import 'sport_chip_picker.dart';

/// Panel de preferencias MatchPay.
/// Orden: país → idioma → moneda → deporte (identidad regional primero).
/// [showSport] solo tiene sentido para organizadores.
class MatchPayPreferencesPanel extends StatelessWidget {
  final bool showSport;
  final bool showCurrency;

  const MatchPayPreferencesPanel({
    super.key,
    this.showSport = true,
    this.showCurrency = true,
  });

  static String _safeCurrencyCode(String code) {
    final ok = CurrencyConfig.options.any((c) => c.code == code);
    return ok ? code : CurrencyConfig.defaultCode;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final l10n = context.l10n;
    final lang = settings.locale.languageCode;
    final locale = AppSettingsController.normalizePickerLocale(settings.locale);
    final currencyCode = _safeCurrencyCode(settings.currencyCode);
    final countryCode = CountrySportCatalog.optionFor(settings.countryCode).code;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.tr('countryLabel'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.tr('countryHint'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('country-$countryCode'),
          initialValue: countryCode,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: CountrySportCatalog.options
              .map(
                (c) => DropdownMenuItem(
                  value: c.code,
                  child: Text(c.labelForLang(lang)),
                ),
              )
              .toList(),
          onChanged: (code) {
            if (code != null) settings.setCountry(code);
          },
        ),
        const SizedBox(height: 20),
        Text(l10n.languageLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<Locale>(
          initialValue: locale,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: AppSettingsController.pickerLocales
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(switch (item.languageCode) {
                    'es' => l10n.tr('langEs'),
                    'en' => l10n.tr('langEn'),
                    'pt' => l10n.tr('langPt'),
                    _ => item.languageCode,
                  }),
                ),
              )
              .toList(),
          onChanged: (next) async {
            if (next != null) {
              await settings.setLocale(next);
              await NotificationService.instance.syncSchedule();
            }
          },
        ),
        if (showCurrency) ...[
          const SizedBox(height: 20),
          Text(l10n.currencyLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: currencyCode,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: CurrencyConfig.options
                .map(
                  (c) => DropdownMenuItem(
                    value: c.code,
                    child: Text(
                      '${c.symbol} ${c.code} — ${c.nameEs}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (code) {
              if (code != null) settings.setCurrency(code);
            },
          ),
        ],
        if (showSport) ...[
          const SizedBox(height: 20),
          Text(l10n.sportLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            l10n.tr('primarySportHint'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          SportChipPicker(
            value: settings.sport,
            onChanged: settings.setSport,
          ),
        ],
      ],
    );
  }
}
