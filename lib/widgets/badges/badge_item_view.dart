import 'package:flutter/material.dart';

import '../../core/matchpay_design_tokens.dart';
import '../../domain/player_profile_badges.dart';
import '../../l10n/matchpay_strings.dart';

/// Chip / ficha individual de insignia para la vitrina.
///
/// Consume [PlayerBadgeDefinition] + estado de desbloqueo/progresión
/// (vía [PlayerBehaviorBadgeView] o campos explícitos).
class BadgeItemView extends StatelessWidget {
  final PlayerBadgeDefinition definition;
  final bool unlocked;
  final int? level;
  final int? maxLevel;
  final double? levelProgress;

  const BadgeItemView({
    super.key,
    required this.definition,
    required this.unlocked,
    this.level,
    this.maxLevel,
    this.levelProgress,
  });

  factory BadgeItemView.fromView(
    PlayerBehaviorBadgeView view, {
    Key? key,
  }) {
    return BadgeItemView(
      key: key,
      definition: view.definition,
      unlocked: view.unlocked,
      level: view.level,
      maxLevel: view.maxLevel,
      levelProgress: view.levelProgress,
    );
  }

  bool get _hasLevels =>
      maxLevel != null && maxLevel! > 0 && definition.hasLevels;

  bool get _isMaxed =>
      _hasLevels && level != null && level! >= maxLevel!;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = _RarityColors.of(definition.rarity);
    final title = l10n.tr(definition.titleKey);
    final body = l10n.tr(definition.bodyKey);

    final borderColor = unlocked
        ? colors.border
        : MatchPayTokens.borderSubtle;
    final fillColor = unlocked
        ? colors.fill
        : MatchPayTokens.surfaceInset;

    Widget emoji = Text(
      definition.emoji,
      style: TextStyle(
        fontSize: 26,
        color: unlocked ? null : Colors.grey.shade500,
      ),
    );
    if (!unlocked) {
      emoji = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 0.85, 0,
        ]),
        child: emoji,
      );
    }

    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: unlocked && definition.rarity.index >= BadgeRarity.epic.index
                ? 1.5
                : 1,
          ),
          boxShadow: unlocked && definition.rarity == BadgeRarity.legendary
              ? [
                  BoxShadow(
                    color: colors.border.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_hasLevels && unlocked && !_isMaxed)
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                        value: (levelProgress ?? 0).clamp(0.0, 1.0),
                        strokeWidth: 3,
                        backgroundColor: colors.border.withValues(alpha: 0.15),
                        color: colors.border,
                      ),
                    ),
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: unlocked
                          ? Colors.white.withValues(alpha: 0.65)
                          : MatchPayTokens.surfaceCard,
                    ),
                    child: emoji,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MatchPayTokens.titleSmallStyle().copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: unlocked
                    ? MatchPayTokens.ink
                    : MatchPayTokens.inkMuted,
              ),
            ),
            if (_hasLevels) ...[
              const SizedBox(height: 4),
              Text(
                _isMaxed
                    ? _maxLabel(context)
                    : _levelLabel(context, level ?? 0),
                style: MatchPayTokens.bodySmallStyle(
                  color: unlocked ? colors.ink : MatchPayTokens.inkMuted,
                ).copyWith(fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
              if (unlocked && !_isMaxed) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (levelProgress ?? 0).clamp(0.0, 1.0),
                    minHeight: 3.5,
                    backgroundColor: colors.border.withValues(alpha: 0.18),
                    color: colors.border,
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.inkSecondary,
                ).copyWith(fontSize: 10.5, height: 1.25),
              ),
            ],
            if (!unlocked) ...[
              const SizedBox(height: 6),
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: MatchPayTokens.inkMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _levelLabel(BuildContext context, int level) {
    final roman = badgeLevelLabel(level);
    if (roman.isEmpty) return _lockedLevel(context);
    final lang = Localizations.localeOf(context).languageCode;
    return switch (lang) {
      'en' => 'Level $roman',
      'pt' => 'Nível $roman',
      _ => 'Nivel $roman',
    };
  }

  String _maxLabel(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return switch (lang) {
      'en' => 'Max',
      'pt' => 'Máx.',
      _ => 'Completado',
    };
  }

  String _lockedLevel(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return switch (lang) {
      'en' => 'Locked',
      'pt' => 'Bloqueado',
      _ => 'Bloqueado',
    };
  }
}

class _RarityColors {
  final Color fill;
  final Color border;
  final Color ink;

  const _RarityColors({
    required this.fill,
    required this.border,
    required this.ink,
  });

  factory _RarityColors.of(BadgeRarity rarity) {
    return switch (rarity) {
      BadgeRarity.common => const _RarityColors(
          fill: Color(0xFFF7F8FA),
          border: Color(0xFFD1D5DB),
          ink: Color(0xFF4B5563),
        ),
      BadgeRarity.uncommon => const _RarityColors(
          fill: Color(0xFFECFDF5),
          border: Color(0xFF34D399),
          ink: Color(0xFF047857),
        ),
      BadgeRarity.rare => const _RarityColors(
          fill: Color(0xFFEFF6FF),
          border: Color(0xFF60A5FA),
          ink: Color(0xFF1D4ED8),
        ),
      BadgeRarity.epic => const _RarityColors(
          fill: Color(0xFFF5F3FF),
          border: Color(0xFFA78BFA),
          ink: Color(0xFF6D28D9),
        ),
      BadgeRarity.legendary => const _RarityColors(
          fill: Color(0xFFFFFBEB),
          border: Color(0xFFFBBF24),
          ink: Color(0xFFB45309),
        ),
    };
  }
}
