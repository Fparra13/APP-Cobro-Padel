import 'package:flutter/material.dart';

import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Selector del deporte de un partido/convocatoria (no la preferencia global).
class MatchSportPicker extends StatelessWidget {
  final SportType value;
  final ValueChanged<SportType>? onChanged;
  final bool enabled;

  const MatchSportPicker({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.readSettings().locale.languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('matchSportLabel'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SportType.values.map((sport) {
            final palette = SportThemeConfig.paletteFor(sport);
            final selected = value == sport;
            return ChoiceChip(
              avatar: Text(palette.emoji, style: const TextStyle(fontSize: 14)),
              label: Text(sport.labelForLocale(lang)),
              selected: selected,
              onSelected: !enabled || onChanged == null
                  ? null
                  : (_) => onChanged!(sport),
              selectedColor: palette.surfaceTint,
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}
