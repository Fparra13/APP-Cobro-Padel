import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/acquisition_controller.dart';
import '../../core/auth_service.dart';
import '../../core/supabase_config.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../widgets/kloovi_brand.dart';
import '../../widgets/matchpay_ui.dart';

/// Pantalla cold start: propuesta de valor + caminos organizador / participante.
class AcquisitionScreen extends StatelessWidget {
  const AcquisitionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = SportThemeConfig.paletteFor(SportType.general);

    return Theme(
      data: SportThemeConfig.themeFor(SportType.general),
      child: Scaffold(
        backgroundColor: MatchPayTokens.surfaceBase,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 1),
                const KlooviSplashLogo(height: 120, maxWidth: 300),
                const SizedBox(height: 28),
                Text(
                  l10n.tr('acquisitionColdStartTitle'),
                  textAlign: TextAlign.center,
                  style: MatchPayTokens.headlineStyle().copyWith(
                    fontSize: 24,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.tr('acquisitionColdStartSubtitle'),
                  textAlign: TextAlign.center,
                  style: MatchPayTokens.bodySmallStyle().copyWith(
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                _PathCard(
                  icon: Icons.event_available_rounded,
                  iconColor: palette.primary,
                  title: l10n.tr('acquisitionOrganizeFirstMatch'),
                  subtitle: l10n.tr('acquisitionOrganizeFirstMatchSub'),
                  onTap: () => _onOrganize(context),
                ),
                const SizedBox(height: 12),
                _PathCard(
                  icon: Icons.people_rounded,
                  iconColor: MatchPayTokens.accentSuccess,
                  title: l10n.tr('acquisitionImPlayer'),
                  subtitle: l10n.tr('acquisitionImPlayerSub'),
                  onTap: () => _onPlayer(context),
                ),
                const Spacer(flex: 2),
                Text(
                  l10n.tr('acquisitionAlreadyInvitedQuestion'),
                  textAlign: TextAlign.center,
                  style: MatchPayTokens.bodySmallStyle(),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => _onPlayer(context),
                    child: Text(
                      l10n.tr('acquisitionJoinWithInviteLink'),
                      style: MatchPayTokens.bodySmallStyle(
                        color: palette.primaryDark,
                      ).copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: palette.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onOrganize(BuildContext context) async {
    await context.read<AcquisitionController>().chooseCreateFirstGroup();
  }

  Future<void> _onPlayer(BuildContext context) async {
    await context.read<AcquisitionController>().choosePlayer();
  }
}

class _PathCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PathCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MatchPaySurfaceCard(
      elevated: true,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: MatchPayTokens.titleSmallStyle(
                          color: MatchPayTokens.ink,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: MatchPayTokens.bodySmallStyle(
                          color: MatchPayTokens.inkSecondary,
                        ).copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: MatchPayTokens.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra [AcquisitionScreen] en cold start hasta que el usuario elige camino.
class AcquisitionGate extends StatelessWidget {
  final Widget child;

  const AcquisitionGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (SupabaseConfig.isConfigured && AuthService.instance.isLoggedIn) {
      return child;
    }

    final acquisition = context.watch<AcquisitionController>();

    if (!acquisition.isLoaded) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: KlooviSplashLogo(height: 140, maxWidth: 320),
        ),
      );
    }

    if (acquisition.shouldSkipAcquisitionScreen) {
      return child;
    }

    return const AcquisitionScreen();
  }
}
