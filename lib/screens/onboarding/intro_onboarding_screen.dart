import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/acquisition_controller.dart';
import '../../core/app_settings_controller.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../widgets/kloovi_brand.dart';
import '../../widgets/matchpay_ui.dart';
import '../../widgets/onboarding_progress.dart';

/// Intro de valor para organizadores antes del login.
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
    await context.read<AppSettingsController>().completeIntroAndDefaultSport();
  }

  Future<void> _volver() async {
    if (_saving) return;
    await context.read<AppSettingsController>().revertIntroOnboarding();
    if (!mounted) return;
    await context.read<AcquisitionController>().resetColdStartChoice();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = SportThemeConfig.paletteFor(SportType.general);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _volver();
      },
      child: Theme(
        data: SportThemeConfig.themeFor(SportType.general),
        child: Scaffold(
          backgroundColor: MatchPayTokens.surfaceBase,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _volver,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      label: Text(l10n.tr('onboardingBack')),
                    ),
                  ),
                  const SizedBox(height: 4),
                  OnboardingProgress(
                    stepLabel: l10n.tr('introOnboardingStep'),
                    current: 1,
                    total: 1,
                    accent: palette.primary,
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: KlooviBrandHeader(iconSize: 72, wordmarkHeight: 52),
                  ),
                  const SizedBox(height: 20),
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
                          icon: Icons.bar_chart_rounded,
                          color: const Color(0xFF7C3AED),
                          title: l10n.tr('introFeatureStats'),
                          subtitle: l10n.tr('introFeatureStatsSub'),
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
      ),
    );
  }
}
