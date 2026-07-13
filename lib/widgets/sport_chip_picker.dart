import 'package:flutter/material.dart';

import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Chips de deportes destacados + hoja «Ver más» con el catálogo completo.
class SportChipPicker extends StatelessWidget {
  final SportType value;
  final ValueChanged<SportType>? onChanged;
  final bool enabled;
  final String? moreLabel;

  const SportChipPicker({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.moreLabel,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watchSettings();
    final lang = settings.locale.languageCode;
    final label = moreLabel ?? context.l10n.tr('sportSeeMore');
    final featured = settings.featuredSports;
    final valueInFeatured = featured.contains(value);

    final chips = <Widget>[
      for (final sport in featured)
        _SportChoiceChip(
          sport: sport,
          lang: lang,
          selected: value == sport,
          enabled: enabled && onChanged != null,
          onSelected: () => onChanged?.call(sport),
        ),
      if (!valueInFeatured)
        _SportChoiceChip(
          sport: value,
          lang: lang,
          selected: true,
          enabled: enabled && onChanged != null,
          onSelected: () {},
        ),
      ActionChip(
        avatar: const Icon(Icons.grid_view_rounded, size: 16),
        label: Text(label),
        onPressed: !enabled || onChanged == null
            ? null
            : () => _openAllSportsSheet(context, lang),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Future<void> _openAllSportsSheet(BuildContext context, String lang) async {
    final selected = await showModalBottomSheet<SportType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    l10n.tr('sportPickAllTitle'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: SportType.values.length,
                    itemBuilder: (ctx, i) {
                      final sport = SportType.values[i];
                      final palette = SportThemeConfig.paletteFor(sport);
                      final isSelected = sport == value;
                      return ListTile(
                        leading: Text(
                          palette.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(sport.labelForLocale(lang)),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle_rounded,
                                color: palette.primary,
                              )
                            : null,
                        selected: isSelected,
                        onTap: () => Navigator.pop(ctx, sport),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected != null) onChanged?.call(selected);
  }
}

class _SportChoiceChip extends StatelessWidget {
  final SportType sport;
  final String lang;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  const _SportChoiceChip({
    required this.sport,
    required this.lang,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SportThemeConfig.paletteFor(sport);
    // Avatar simple (emoji/texto): evita asserts de layout con
    // avatarBoxConstraints tight + SizedBox anidados en ChoiceChip.
    return ChoiceChip(
      avatar: Text(palette.emoji, style: const TextStyle(fontSize: 14)),
      label: Text(sport.labelForLocale(lang)),
      selected: selected,
      onSelected: !enabled
          ? null
          : (isSelected) {
              if (isSelected) onSelected();
            },
      selectedColor: palette.surfaceTint,
      showCheckmark: false,
    );
  }
}
