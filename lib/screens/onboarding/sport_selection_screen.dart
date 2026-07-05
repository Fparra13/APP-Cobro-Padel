import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_settings_controller.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../utils/matchpay_context.dart';
import 'intro_onboarding_screen.dart';

/// Paso 2 del onboarding: el usuario elige su deporte principal (solo visual).
class SportSelectionScreen extends StatefulWidget {
  const SportSelectionScreen({super.key});

  @override
  State<SportSelectionScreen> createState() => _SportSelectionScreenState();
}

class _SportSelectionScreenState extends State<SportSelectionScreen> {
  SportType? _selected;
  bool _saving = false;

  Future<void> _continuar() async {
    final sport = _selected;
    if (sport == null || _saving) return;

    setState(() => _saving = true);
    await context.read<AppSettingsController>().completeSportOnboarding(sport);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = _selected ?? SportType.general;
    final palette = SportThemeConfig.paletteFor(preview);

    return Theme(
      data: SportThemeConfig.themeFor(preview),
      child: Scaffold(
        backgroundColor: MatchPayTokens.surfaceBase,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.tr('sportOnboardingStep'),
                  style: MatchPayTokens.sectionLabelStyle(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.sportOnboardingTitle,
                  style: MatchPayTokens.displayStyle(color: palette.primaryDark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.sportOnboardingSubtitle,
                  style: MatchPayTokens.bodySmallStyle(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: SportType.values.map(_buildSportCard).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _selected == null || _saving ? null : _continuar,
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
                      : Text(l10n.sportOnboardingContinue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSportCard(SportType sport) {
    final palette = SportThemeConfig.paletteFor(sport);
    final selected = _selected == sport;
    final lang = context.readSettings().locale.languageCode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? palette.cardBackground : Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: selected ? 2 : 0,
        child: InkWell(
          onTap: () => setState(() => _selected = sport),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? palette.primary : Colors.grey.shade200,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      palette.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sport.labelForLocale(lang),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: palette.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sportDescription(sport),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? palette.primary : Colors.grey.shade400,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _sportDescription(SportType sport) {
    return switch (sport) {
      SportType.padel => context.l10n.sportDescPadel,
      SportType.football => context.l10n.sportDescFootball,
      SportType.tennis => context.l10n.sportDescTennis,
      SportType.general => context.l10n.sportDescGeneral,
    };
  }
}

/// Onboarding: intro de valor → deporte → login / app.
class SportOnboardingGate extends StatelessWidget {
  final Widget child;

  const SportOnboardingGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();

    if (!settings.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!settings.introOnboardingComplete) {
      return const IntroOnboardingScreen();
    }

    if (!settings.sportOnboardingComplete) {
      return const SportSelectionScreen();
    }

    return child;
  }
}
