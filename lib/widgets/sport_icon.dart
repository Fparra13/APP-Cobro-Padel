import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/expense_icon.dart';
import '../core/app_settings_controller.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../utils/matchpay_context.dart';

/// Icono Material según el deporte activo (o el indicado).
class SportIcon extends StatelessWidget {
  final SportType? sport;
  final double size;
  final Color? color;

  const SportIcon({
    super.key,
    this.sport,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final s = sport ?? context.read<AppSettingsController>().sport;
    return Icon(s.icon, size: size, color: color);
  }
}

/// Emoji del deporte (paleta MatchPay).
class SportEmoji extends StatelessWidget {
  final SportType? sport;
  final double size;

  const SportEmoji({
    super.key,
    this.sport,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final s = sport ?? context.read<AppSettingsController>().sport;
    return Text(
      SportThemeConfig.paletteFor(s).emoji,
      style: TextStyle(fontSize: size),
    );
  }
}

/// Etiqueta compacta de deporte en tarjetas de cobro.
class SportChargeChip extends StatelessWidget {
  final SportType sport;

  const SportChargeChip({super.key, required this.sport});

  @override
  Widget build(BuildContext context) {
    final palette = SportThemeConfig.paletteFor(sport);
    final lang = context.read<AppSettingsController>().locale.languageCode;
    final label = sport.labelForLocale(lang);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(palette.emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icono de cancha/recinto según deporte.
IconData sportVenueIcon(SportType sport) => ExpenseIconKey.courtIconFor(sport);

/// Icono de pelotas/equipamiento según deporte.
IconData sportBallsIcon(SportType sport) => ExpenseIconKey.ballsIconFor(sport);
