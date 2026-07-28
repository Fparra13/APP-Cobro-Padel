import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import 'sport_chip_picker.dart';

/// Selector de actividad del encuentro (UI: actividad; código: [SportType]).
///
/// [compact]: tarjeta que abre el catálogo en un sheet (create encuentro).
class MatchSportPicker extends StatelessWidget {
  final SportType? value;
  final ValueChanged<SportType>? onChanged;
  final bool enabled;
  final bool compact;

  const MatchSportPicker({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactActivityCard(
        value: value,
        enabled: enabled && onChanged != null,
        onTap: () => _openActivitySheet(context),
      );
    }

    final l10n = context.l10n;
    final selected = value ?? SportType.other;

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
        SportChipPicker(
          value: selected,
          onChanged: onChanged,
          enabled: enabled,
        ),
      ],
    );
  }

  Future<void> _openActivitySheet(BuildContext context) async {
    if (onChanged == null || !enabled) return;
    final l10n = context.l10n;
    final selected = await showModalBottomSheet<SportType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (sheetCtx, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    l10n.tr('matchActivityPrompt'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    l10n.tr('matchActivitySubtitle'),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      SportChipPicker(
                        // Valor neutro solo para layout; no se resalta sin selección.
                        value: value ?? SportType.padel,
                        highlightSelection: value != null,
                        // Un solo camino al catálogo: «Otra actividad».
                        showMoreChip: false,
                        excludeOther: true,
                        onChanged: (sport) => Navigator.pop(sheetCtx, sport),
                        enabled: true,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _pickFromFullCatalog(sheetCtx),
                        child: Text(l10n.tr('sportOtherActivity')),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected != null) onChanged!(selected);
  }

  /// Abre el catálogo completo sin cerrar el sheet de actividad ni
  /// seleccionar [SportType.other] de forma temporal.
  Future<void> _pickFromFullCatalog(BuildContext sheetContext) async {
    final picked = await SportChipPicker.openFullCatalog(
      sheetContext,
      current: value,
      // «Otro» no es una actividad elegible aquí; el botón solo abre el catálogo.
      excludeOther: true,
    );
    if (picked == null) return;
    if (!sheetContext.mounted) return;
    Navigator.pop(sheetContext, picked);
  }
}

class _CompactActivityCard extends StatelessWidget {
  final SportType? value;
  final bool enabled;
  final VoidCallback onTap;

  const _CompactActivityCard({
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final selected = value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
            border: Border.all(color: MatchPayTokens.borderSubtle),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.tr('matchSportLabel'),
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkMuted,
                ).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                selected != null
                    ? '${SportThemeConfig.paletteFor(selected).emoji} '
                        '${selected.labelForLang(lang)}'
                    : l10n.tr('matchActivityPrompt'),
                style: MatchPayTokens.titleSmallStyle().copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    selected != null
                        ? l10n.tr('matchActivityChange')
                        : l10n.tr('matchActivityChoose'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1AA89B),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: MatchPayTokens.inkMuted,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
