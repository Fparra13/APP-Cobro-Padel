import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_settings_controller.dart';
import '../../core/sport_theme.dart';
import '../../core/sport_type.dart';
import '../../l10n/matchpay_strings.dart';
import '../../utils/matchpay_context.dart';

/// Primera pantalla de la app: el usuario elige su deporte principal.
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
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.sportOnboardingTitle,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: palette.primaryDark,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.sportOnboardingSubtitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
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
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? palette.primary : Colors.grey.shade200,
                width: selected ? 2 : 1,
              ),
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
                    child: Text(palette.emoji, style: const TextStyle(fontSize: 28)),
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

/// Muestra el selector de deporte antes que login o la app principal.
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

    if (!settings.sportOnboardingComplete) {
      return const SportSelectionScreen();
    }

    return child;
  }
}
