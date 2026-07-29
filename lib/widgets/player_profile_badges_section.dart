import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../domain/player_profile_badges.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Insignias de comportamiento desbloqueadas (y metas privadas atenuadas).
class PlayerProfileBadgesSection extends StatelessWidget {
  final List<PlayerBehaviorBadgeView> badges;

  const PlayerProfileBadgesSection({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unlocked = badges.where((b) => b.unlocked).length;
    final palette = context.sportPalette;

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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        const SizedBox(height: 10),
        if (unlocked == 0)
          MatchPaySurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              l10n.tr('playerProfileBadgesEmpty'),
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.inkSecondary,
              ),
            ),
          ),
        ...badges.map(
          (badge) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BadgeCard(badge: badge),
          ),
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final PlayerBehaviorBadgeView badge;

  const _BadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final unlocked = badge.unlocked;

    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: MatchPaySurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: unlocked
                    ? palette.primary.withValues(alpha: 0.12)
                    : MatchPayTokens.surfaceInset,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: unlocked
                      ? palette.primary.withValues(alpha: 0.25)
                      : MatchPayTokens.borderSubtle,
                ),
              ),
              child: Text(
                badge.emoji,
                style: TextStyle(
                  fontSize: 22,
                  color: unlocked ? null : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.tr(badgeTitleKey(badge.id)),
                          style: MatchPayTokens.titleSmallStyle().copyWith(
                            fontSize: 13.5,
                            color: unlocked
                                ? MatchPayTokens.ink
                                : MatchPayTokens.inkMuted,
                          ),
                        ),
                      ),
                      Icon(
                        unlocked
                            ? Icons.check_circle_rounded
                            : Icons.lock_outline_rounded,
                        size: 18,
                        color: unlocked
                            ? MatchPayTokens.accentSuccess
                            : MatchPayTokens.inkMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.tr(badgeBodyKey(badge.id)),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.inkSecondary,
                    ).copyWith(fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
