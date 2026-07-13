import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/acquisition_controller.dart';
import '../../core/app_settings_controller.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../utils/matchpay_context.dart';
import '../../widgets/matchpay_ui.dart';
import '../../widgets/onboarding_progress.dart';
import 'intro_onboarding_screen.dart';
import 'player_intro_onboarding_screen.dart';

/// Paso 2 del onboarding: el usuario elige su deporte principal (tema visual).
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

  Future<void> _volverAlPaso1() async {
    if (_saving) return;
    await context.read<AppSettingsController>().revertIntroOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preview = _selected ?? SportType.general;
    final palette = SportThemeConfig.paletteFor(preview);
    final lang = context.select<AppSettingsController, String>(
      (s) => s.locale.languageCode,
    );
    final featured = context.select<AppSettingsController, List<SportType>>(
      (s) => s.featuredSports,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _volverAlPaso1();
      },
      child: Theme(
        data: SportThemeConfig.themeFor(preview),
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
                      onPressed: _saving ? null : _volverAlPaso1,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      label: Text(l10n.tr('onboardingBack')),
                    ),
                  ),
                  const SizedBox(height: 4),
                OnboardingProgress(
                  stepLabel: l10n.tr('sportOnboardingStep'),
                  current: 2,
                  total: 2,
                  accent: palette.primary,
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
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: _selected == null
                      ? const SizedBox.shrink(key: ValueKey('no-preview'))
                      : _SportPreviewBanner(
                          key: ValueKey(_selected),
                          sport: _selected!,
                          lang: lang,
                          label: l10n.tr('sportOnboardingPreview'),
                        ),
                ),
                if (_selected != null) const SizedBox(height: 16),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.88,
                    children: [
                      ...featured.map(
                        (sport) => _buildSportTile(sport, lang),
                      ),
                      if (_selected != null && !featured.contains(_selected))
                        _buildSportTile(_selected!, lang),
                      _buildSeeMoreTile(lang),
                    ],
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
      ),
    );
  }

  Widget _buildSportTile(SportType sport, String lang) {
    final palette = SportThemeConfig.paletteFor(sport);
    final selected = _selected == sport;

    return Material(
      color: selected ? palette.cardBackground : Colors.white,
      borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
      child: InkWell(
        onTap: () => setState(() => _selected = sport),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
            border: Border.all(
              color: selected ? palette.primary : MatchPayTokens.borderSubtle,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? palette.primary : MatchPayTokens.inkMuted,
                  size: 22,
                ),
              ),
              Text(palette.emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                sport.labelForLocale(lang),
                style: MatchPayTokens.titleSmallStyle(
                  color: palette.primaryDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _sportDescription(sport),
                style: MatchPayTokens.bodySmallStyle(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeeMoreTile(String lang) {
    final l10n = context.l10n;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
      child: InkWell(
        onTap: () => _openAllSportsSheet(lang),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
            border: Border.all(color: MatchPayTokens.borderSubtle),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 36,
                color: MatchPayTokens.inkMuted,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.tr('sportSeeMore'),
                style: MatchPayTokens.titleSmallStyle(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.tr('sportSeeMoreHint'),
                style: MatchPayTokens.bodySmallStyle(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAllSportsSheet(String lang) async {
    final selected = await showModalBottomSheet<SportType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
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
                    ctx.l10n.tr('sportPickAllTitle'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: SportType.values.length,
                    itemBuilder: (ctx, i) {
                      final sport = SportType.values[i];
                      final palette = SportThemeConfig.paletteFor(sport);
                      final isSelected = sport == _selected;
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
    if (selected != null && mounted) {
      setState(() => _selected = selected);
    }
  }

  String _sportDescription(SportType sport) {
    final l10n = context.l10n;
    return switch (sport) {
      SportType.padel => l10n.sportDescPadel,
      SportType.football => l10n.sportDescFootball,
      SportType.tennis => l10n.sportDescTennis,
      SportType.other => l10n.sportDescGeneral,
      _ => l10n.tr('sportDescGeneric'),
    };
  }
}

class _SportPreviewBanner extends StatelessWidget {
  final SportType sport;
  final String lang;
  final String label;

  const _SportPreviewBanner({
    super.key,
    required this.sport,
    required this.lang,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SportThemeConfig.paletteFor(sport);
    final name = sport.labelForLocale(lang);

    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: MatchPayTokens.sectionLabelStyle(accent: true),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(palette.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: MatchPayTokens.titleSmallStyle(
                        color: palette.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _ColorDot(color: palette.primary),
                        const SizedBox(width: 6),
                        _ColorDot(color: palette.accent),
                        const SizedBox(width: 6),
                        _ColorDot(color: palette.surfaceTint),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: palette.primary,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
            ),
            child: Row(
              children: [
                Icon(Icons.home_rounded, color: Colors.white.withValues(alpha: 0.9), size: 18),
                const SizedBox(width: 8),
                Text(
                  context.l10n.navHome,
                  style: MatchPayTokens.titleSmallStyle(color: Colors.white),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    context.l10n.appName,
                    style: MatchPayTokens.statValueStyle(
                      color: palette.primaryDark,
                    ).copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: MatchPayTokens.borderSubtle),
      ),
    );
  }
}

/// Onboarding: intro de valor (según rol) → login / app. Deporte por defecto.
class SportOnboardingGate extends StatefulWidget {
  final Widget child;

  const SportOnboardingGate({super.key, required this.child});

  @override
  State<SportOnboardingGate> createState() => _SportOnboardingGateState();
}

class _SportOnboardingGateState extends State<SportOnboardingGate> {
  bool _autoCompleting = false;

  Future<void> _autoCompletePendingSteps() async {
    if (!mounted || _autoCompleting) return;
    final settings = context.read<AppSettingsController>();
    final acq = context.read<AcquisitionController>();

    final skipIntro = acq.skipIntroOnboarding && !settings.introOnboardingComplete;
    final skipSport = !settings.sportOnboardingComplete;

    if (!skipIntro && !skipSport) return;

    setState(() => _autoCompleting = true);
    if (skipIntro) {
      await settings.completeIntroAndDefaultSport();
    } else if (skipSport) {
      await settings.completeSportOnboarding(SportType.general);
    }
    if (mounted) setState(() => _autoCompleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final acq = context.watch<AcquisitionController>();

    if (!settings.isLoaded || _autoCompleting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!settings.introOnboardingComplete) {
      if (acq.skipIntroOnboarding) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _autoCompletePendingSteps();
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      if (acq.intent == MatchPayAcquisitionIntent.createFirstGroup) {
        return const IntroOnboardingScreen();
      }
      return const PlayerIntroOnboardingScreen();
    }

    if (!settings.sportOnboardingComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoCompletePendingSteps();
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return widget.child;
  }
}
