import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/currency_config.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../services/notification_service.dart';
import '../utils/matchpay_context.dart';

/// Panel de preferencias MatchPay.
/// [showSport] solo tiene sentido para organizadores (deporte al crear partidos).
class MatchPayPreferencesPanel extends StatelessWidget {
  final bool showSport;
  final bool showCurrency;

  const MatchPayPreferencesPanel({
    super.key,
    this.showSport = true,
    this.showCurrency = true,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final l10n = context.l10n;
    final lang = settings.locale.languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        if (showSport) ...[
          Text(l10n.sportLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            l10n.tr('primarySportHint'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SportType.values.map((sport) {
              final palette = SportThemeConfig.paletteFor(sport);
              return ChoiceChip(
                avatar: Text(palette.emoji, style: const TextStyle(fontSize: 14)),
                label: Text(sport.labelForLocale(lang)),
                selected: settings.sport == sport,
                onSelected: (_) => settings.setSport(sport),
                selectedColor: palette.surfaceTint,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
        Text(l10n.languageLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<Locale>(
          value: _matchLocale(settings.locale),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            DropdownMenuItem(
              value: const Locale('es', 'CL'),
              child: Text(l10n.tr('langEs')),
            ),
            DropdownMenuItem(
              value: const Locale('en'),
              child: Text(l10n.tr('langEn')),
            ),
            DropdownMenuItem(
              value: const Locale('pt', 'BR'),
              child: Text(l10n.tr('langPt')),
            ),
          ],
          onChanged: (locale) async {
            if (locale != null) {
              await settings.setLocale(locale);
              await NotificationService.instance.syncSchedule();
            }
          },
        ),
        if (showCurrency) ...[
          const SizedBox(height: 20),
          Text(l10n.currencyLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: settings.currencyCode,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: CurrencyConfig.options
                .map(
                  (c) => DropdownMenuItem(
                    value: c.code,
                    child: Text('${c.symbol} ${c.code} — ${c.nameEs}'),
                  ),
                )
                .toList(),
            onChanged: (code) {
              if (code != null) settings.setCurrency(code);
            },
          ),
        ],
      ],
    );
  }

  static Locale _matchLocale(Locale locale) {
    for (final supported in const [
      Locale('es', 'CL'),
      Locale('en'),
      Locale('pt', 'BR'),
    ]) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return const Locale('es', 'CL');
  }
}
