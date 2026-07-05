import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_settings_controller.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../widgets/matchpay_ui.dart';

/// Paso 1 del onboarding: explica el valor de MatchPay antes de elegir deporte.
class IntroOnboardingScreen extends StatefulWidget {
  const IntroOnboardingScreen({super.key});

  @override
  State<IntroOnboardingScreen> createState() => _IntroOnboardingScreenState();
}

class _IntroOnboardingScreenState extends State<IntroOnboardingScreen> {
  bool _saving = false;

  Future<void> _continuar() async {
    if (_saving) return;
    setState(() => _saving = true);
    await context.read<AppSettingsController>().completeIntroOnboarding();
  }

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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.tr('introOnboardingStep'),
                  style: MatchPayTokens.sectionLabelStyle(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.appName,
                  style: MatchPayTokens.displayStyle(color: palette.primaryDark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.tr('introOnboardingTitle'),
                  style: MatchPayTokens.headlineStyle().copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tr('introOnboardingSubtitle'),
                  style: MatchPayTokens.bodySmallStyle(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: ListView(
                    children: [
                      MatchPayFeatureRow(
                        icon: Icons.event_available_rounded,
                        color: palette.primary,
                        title: l10n.tr('introFeatureOrganize'),
                        subtitle: l10n.tr('introFeatureOrganizeSub'),
                      ),
                      const SizedBox(height: 12),
                      MatchPayFeatureRow(
                        icon: Icons.how_to_reg_rounded,
                        color: MatchPayTokens.accentSuccess,
                        title: l10n.tr('introFeatureConfirm'),
                        subtitle: l10n.tr('introFeatureConfirmSub'),
                      ),
                      const SizedBox(height: 12),
                      MatchPayFeatureRow(
                        icon: Icons.payments_rounded,
                        color: MatchPayTokens.accentUrgent,
                        title: l10n.tr('introFeaturePay'),
                        subtitle: l10n.tr('introFeaturePaySub'),
                      ),
                      const SizedBox(height: 12),
                      MatchPayFeatureRow(
                        icon: Icons.groups_rounded,
                        color: const Color(0xFF7C3AED),
                        title: l10n.tr('introFeatureGroups'),
                        subtitle: l10n.tr('introFeatureGroupsSub'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _continuar,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(MatchPayTokens.radiusButton),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.tr('introOnboardingContinue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
