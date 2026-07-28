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
  /// Si false, no marca ningún chip como seleccionado (p. ej. aún sin elegir).
  final bool highlightSelection;
  /// Muestra el ActionChip «Ver todas…» (p. ej. preferencias).
  /// En Organizar encuentro se oculta: la única vía es «Otra actividad».
  final bool showMoreChip;
  /// No muestra [SportType.other] como chip destacado.
  final bool excludeOther;

  const SportChipPicker({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.moreLabel,
    this.highlightSelection = true,
    this.showMoreChip = true,
    this.excludeOther = false,
  });

  /// Catálogo completo (sheet). Usado por «Ver todas» (otros flujos) y
  /// «Otra actividad» (Organizar encuentro).
  static Future<SportType?> openFullCatalog(
    BuildContext context, {
    SportType? current,
    bool excludeOther = false,
  }) {
    final sports = SportType.values
        .where((s) => !excludeOther || s != SportType.other)
        .toList(growable: false);

    return showModalBottomSheet<SportType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final l10n = ctx.l10n;
        final lang = Localizations.localeOf(ctx).languageCode;
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
                    itemCount: sports.length,
                    itemBuilder: (ctx, i) {
                      final sport = sports[i];
                      final palette = SportThemeConfig.paletteFor(sport);
                      final isSelected = current != null && sport == current;
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
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watchSettings();
    final lang = settings.locale.languageCode;
    final label = moreLabel ?? context.l10n.tr('sportSeeMore');
    final featured = settings.featuredSports
        .where((s) => !excludeOther || s != SportType.other)
        .toList(growable: false);
    final valueInFeatured = featured.contains(value);
    final showSelected = highlightSelection;
    // No pintar chip huérfano de «Otro» cuando está excluido de destacados.
    final showValueChip = showSelected &&
        !valueInFeatured &&
        !(excludeOther && value == SportType.other);

    final chips = <Widget>[
      for (final sport in featured)
        _SportChoiceChip(
          sport: sport,
          lang: lang,
          selected: showSelected && value == sport,
          enabled: enabled && onChanged != null,
          onSelected: () => onChanged?.call(sport),
        ),
      if (showValueChip)
        _SportChoiceChip(
          sport: value,
          lang: lang,
          selected: true,
          enabled: enabled && onChanged != null,
          onSelected: () {},
        ),
      if (showMoreChip)
        ActionChip(
          avatar: const Icon(Icons.grid_view_rounded, size: 16),
          label: Text(label),
          onPressed: !enabled || onChanged == null
              ? null
              : () async {
                  final selected = await openFullCatalog(
                    context,
                    current: highlightSelection ? value : null,
                    excludeOther: excludeOther,
                  );
                  if (selected != null) onChanged?.call(selected);
                },
        ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
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
