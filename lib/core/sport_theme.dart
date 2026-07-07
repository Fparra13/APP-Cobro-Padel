import 'package:flutter/material.dart';

import 'matchpay_design_tokens.dart';
import 'sport_type.dart';

/// Paleta visual por deporte para MatchPay.
class SportThemePalette {
  final Color primary;
  final Color primaryDark;
  final Color accent;
  final Color cardBackground;
  final Color surfaceTint;
  final Color chipBackground;
  final String emoji;

  const SportThemePalette({
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.cardBackground,
    required this.surfaceTint,
    required this.chipBackground,
    required this.emoji,
  });
}

/// Configuración de temas dinámicos por deporte.
class SportThemeConfig {
  SportThemeConfig._();

  static const palettes = <SportType, SportThemePalette>{
    SportType.padel: SportThemePalette(
      primary: Color(0xFF00838F),
      primaryDark: Color(0xFF006064),
      accent: Color(0xFF80DEEA),
      cardBackground: Color(0xFFE0F7FA),
      surfaceTint: Color(0xFFB2EBF2),
      chipBackground: Color(0xFFE0F2F1),
      emoji: '🎾',
    ),
    SportType.football: SportThemePalette(
      primary: Color(0xFF2E7D32),
      primaryDark: Color(0xFF1B5E20),
      accent: Color(0xFFFFFFFF),
      cardBackground: Color(0xFFE8F5E9),
      surfaceTint: Color(0xFFC8E6C9),
      chipBackground: Color(0xFFF1F8E9),
      emoji: '⚽',
    ),
    SportType.tennis: SportThemePalette(
      primary: Color(0xFFF9A825),
      primaryDark: Color(0xFFF57F17),
      accent: Color(0xFFFFF59D),
      cardBackground: Color(0xFFFFFDE7),
      surfaceTint: Color(0xFFFFF9C4),
      chipBackground: Color(0xFFFFF8E1),
      emoji: '🎾',
    ),
    SportType.general: SportThemePalette(
      primary: Color(0xFF1565C0),
      primaryDark: Color(0xFF0D47A1),
      accent: Color(0xFF64B5F6),
      cardBackground: Color(0xFFE3F2FD),
      surfaceTint: Color(0xFFBBDEFB),
      chipBackground: Color(0xFFE8EAF6),
      emoji: '🏆',
    ),
  };

  static SportThemePalette paletteFor(SportType sport) =>
      palettes[sport] ?? palettes[SportType.general]!;

  static ThemeData themeFor(SportType sport) {
    final p = paletteFor(sport);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      primary: p.primary,
      secondary: p.accent,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: MatchPayTokens.surfaceBase,
      textTheme: MatchPayTokens.applyTextTheme(
        ThemeData.light().textTheme,
      ),
      cardTheme: CardThemeData(
        color: p.cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
          side: BorderSide(color: p.surfaceTint.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: MatchPayTokens.titleMediumStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        foregroundColor: Colors.white,
        backgroundColor: p.primary,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: MatchPayTokens.headlineStyle(color: Colors.white)
            .copyWith(fontSize: 20),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.chipBackground,
        selectedColor: p.accent.withValues(alpha: 0.35),
        labelStyle: TextStyle(color: p.primaryDark),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: p.surfaceTint,
        backgroundColor: Colors.white,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? p.primaryDark : Colors.grey.shade600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? p.primary : Colors.grey.shade600,
          );
        }),
      ),
      extensions: [SportThemeExtension(palette: p)],
    );
  }
}

/// Extensión de tema accesible vía `Theme.of(context).extension<SportThemeExtension>()`.
class SportThemeExtension extends ThemeExtension<SportThemeExtension> {
  final SportThemePalette palette;

  const SportThemeExtension({required this.palette});

  @override
  SportThemeExtension copyWith({SportThemePalette? palette}) =>
      SportThemeExtension(palette: palette ?? this.palette);

  @override
  SportThemeExtension lerp(ThemeExtension<SportThemeExtension>? other, double t) {
    if (other is! SportThemeExtension) return this;
    return this;
  }
}
