import 'package:flutter/material.dart';

import '../../core/matchpay_design_tokens.dart';
import '../../domain/player_profile_badges.dart';
import '../../l10n/matchpay_strings.dart';
import '../../utils/matchpay_context.dart';
import 'badge_item_view.dart';

/// Vitrina de insignias agrupadas por [BadgeCategory].
///
/// Ordena con [sortPlayerBadges] / [badgesForCollection] sobre el estado
/// ya evaluado por el dominio (`buildPlayerBehaviorBadges`).
class BadgeShowcaseBoard extends StatelessWidget {
  final List<PlayerBehaviorBadgeView> badges;

  const BadgeShowcaseBoard({super.key, required this.badges});

  /// Lista ordenada lista para vitrina (displayOrder + visibilidad).
  static List<PlayerBehaviorBadgeView> getOrderedBadges(
    List<PlayerBehaviorBadgeView> evaluated,
  ) =>
      sortPlayerBadges(
        badgesForCollection(evaluated),
        sortBy: BadgeSortBy.displayOrder,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final ordered = getOrderedBadges(badges);
    final unlocked = ordered.where((b) => b.unlocked).length;

    final byCategory = <BadgeCategory, List<PlayerBehaviorBadgeView>>{};
    for (final category in BadgeCategory.values) {
      byCategory[category] = [];
    }
    for (final badge in ordered) {
      byCategory[badge.category]!.add(badge);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tr('playerProfileBadgesTitle'),
                style: MatchPayTokens.titleSmallStyle(),
              ),
            ),
            if (unlocked > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.tr(
                    'playerProfileBadgesCount',
                    params: {'n': '$unlocked'},
                  ),
                  style: MatchPayTokens.bodySmallStyle(
                    color: palette.primaryDark,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
          ],
        ),
        if (ordered.isEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MatchPayTokens.surfaceInset,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MatchPayTokens.borderSubtle),
            ),
            child: Text(
              l10n.tr('playerProfileBadgesEmpty'),
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.inkSecondary,
              ),
            ),
          ),
        ],
        for (final category in BadgeCategory.values)
          if ((byCategory[category] ?? const []).isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _categoryTitle(context, category),
              style: MatchPayTokens.titleSmallStyle().copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: MatchPayTokens.inkSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _categoryHint(context, category),
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.inkMuted,
              ).copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final items = byCategory[category]!;
                final width = constraints.maxWidth;
                const gap = 10.0;
                final cross = width >= 360 ? 3 : 2;
                final tileW = (width - gap * (cross - 1)) / cross;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final badge in items)
                      SizedBox(
                        width: tileW,
                        child: BadgeItemView.fromView(badge),
                      ),
                  ],
                );
              },
            ),
          ],
      ],
    );
  }
}

String _categoryTitle(BuildContext context, BadgeCategory category) {
  final lang = Localizations.localeOf(context).languageCode;
  return switch (category) {
    BadgeCategory.participation => switch (lang) {
        'en' => 'Participation',
        'pt' => 'Participação',
        _ => 'Participación',
      },
    BadgeCategory.consistency => switch (lang) {
        'en' => 'Consistency',
        'pt' => 'Constância',
        _ => 'Constancia',
      },
    BadgeCategory.exploration => switch (lang) {
        'en' => 'Exploration',
        'pt' => 'Exploração',
        _ => 'Exploración',
      },
    BadgeCategory.community => switch (lang) {
        'en' => 'Community',
        'pt' => 'Comunidade',
        _ => 'Comunidad',
      },
    BadgeCategory.milestones => switch (lang) {
        'en' => 'Trajectory',
        'pt' => 'Trajetória',
        _ => 'Trayectoria',
      },
    BadgeCategory.time => switch (lang) {
        'en' => 'Schedule',
        'pt' => 'Horários',
        _ => 'Horarios',
      },
  };
}

String _categoryHint(BuildContext context, BadgeCategory category) {
  final lang = Localizations.localeOf(context).languageCode;
  return switch (category) {
    BadgeCategory.participation => switch (lang) {
        'en' => 'Showing up and staying in the game',
        'pt' => 'Aparecer e permanecer no jogo',
        _ => 'Aparecer y quedarse en el juego',
      },
    BadgeCategory.consistency => switch (lang) {
        'en' => 'Streaks, rhythm and reliability',
        'pt' => 'Sequências, ritmo e constância',
        _ => 'Rachas, ritmo y constancia',
      },
    BadgeCategory.exploration => switch (lang) {
        'en' => 'Sports, venues and new territory',
        'pt' => 'Esportes, complexos e território novo',
        _ => 'Deportes, recintos y territorio nuevo',
      },
    BadgeCategory.community => switch (lang) {
        'en' => 'People you play with',
        'pt' => 'Pessoas com quem você joga',
        _ => 'Personas con las que juegas',
      },
    BadgeCategory.milestones => switch (lang) {
        'en' => 'Milestones across your Kloovi story',
        'pt' => 'Marcos da sua história no Kloovi',
        _ => 'Hitos de tu historia en Kloovi',
      },
    BadgeCategory.time => switch (lang) {
        'en' => 'When you play — hours and seasons',
        'pt' => 'Quando você joga — horários e estações',
        _ => 'Cuándo juegas — horarios y estaciones',
      },
  };
}
