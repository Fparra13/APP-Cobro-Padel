import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/acquisition_controller.dart';
import '../../core/auth_service.dart';
import '../../core/supabase_config.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../widgets/matchpay_ui.dart';

/// Pantalla cold start: propuesta de valor + dos caminos (organizar vs invitado).
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
                Text(
                  l10n.appName,
                  textAlign: TextAlign.center,
                  style: MatchPayTokens.displayStyle(color: palette.primaryDark),
                ),
                const SizedBox(height: 20),
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
                MatchPaySurfaceCard(
                  elevated: true,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _BenefitRow(
                        icon: Icons.campaign_rounded,
                        color: palette.primary,
                        text: l10n.tr('acquisitionBenefitInvite'),
                      ),
                      const SizedBox(height: 12),
                      _BenefitRow(
                        icon: Icons.payments_rounded,
                        color: MatchPayTokens.accentUrgent,
                        text: l10n.tr('acquisitionBenefitCollect'),
                      ),
                      const SizedBox(height: 12),
                      _BenefitRow(
                        icon: Icons.check_circle_outline_rounded,
                        color: MatchPayTokens.accentSuccess,
                        text: l10n.tr('acquisitionBenefitConfirm'),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                FilledButton(
                  onPressed: () => _onCreateGroup(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: palette.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(MatchPayTokens.radiusButton),
                    ),
                  ),
                  child: Text(
                    l10n.tr('acquisitionCreateFirstGroup'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => _onAlreadyInvited(context),
                    child: Text(
                      l10n.tr('acquisitionAlreadyInvited'),
                      style: MatchPayTokens.bodySmallStyle(
                        color: palette.primaryDark,
                      ).copyWith(
                        fontWeight: FontWeight.w600,
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

  Future<void> _onCreateGroup(BuildContext context) async {
    await context.read<AcquisitionController>().chooseCreateFirstGroup();
  }

  Future<void> _onAlreadyInvited(BuildContext context) async {
    await context.read<AcquisitionController>().chooseInvited();
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _BenefitRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              text,
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.inkSecondary,
              ).copyWith(height: 1.35),
            ),
          ),
        ),
      ],
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (acquisition.shouldSkipAcquisitionScreen) {
      return child;
    }

    return const AcquisitionScreen();
  }
}
