import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens visuales compartidos de MatchPay (independientes del deporte).
class MatchPayTokens {
  MatchPayTokens._();

  // ── Superficies ──────────────────────────────────────────────
  static const surfaceBase = Color(0xFFF5F4F0);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const surfaceInset = Color(0xFFFAFAF8);
  static const borderSubtle = Color(0xFFE8E6E1);
  static const borderStrong = Color(0xFFE5E7EB);

  // ── Tipografía / tinta ───────────────────────────────────────
  static const ink = Color(0xFF111827);
  static const inkSecondary = Color(0xFF374151);
  static const inkMuted = Color(0xFF6B7280);

  // ── Estados semánticos ───────────────────────────────────────
  static const accentUrgent = Color(0xFFEA580C);
  static const accentUrgentBg = Color(0xFFFFF7ED);
  static const accentUrgentBorder = Color(0xFFFDBA74);
  static const accentSuccess = Color(0xFF059669);
  static const accentSuccessBg = Color(0xFFECFDF5);
  static const accentCredit = Color(0xFF2563EB);
  static const accentCreditBg = Color(0xFFEFF6FF);
  static const accentError = Color(0xFFDC2626);
  static const accentErrorBg = Color(0xFFFEF2F2);

  // ── Radios ───────────────────────────────────────────────────
  static const radiusHero = 24.0;
  static const radiusCard = 20.0;
  static const radiusCardSm = 16.0;
  static const radiusChip = 12.0;
  static const radiusButton = 14.0;

  // ── Tipografía ─────────────────────────────────────────────────
  static String get fontFamily => GoogleFonts.plusJakartaSans().fontFamily!;

  static TextTheme applyTextTheme(TextTheme base) {
    return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
      displaySmall: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.1,
        color: ink,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.15,
        color: ink,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleSmall: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: inkSecondary,
      ),
      bodySmall: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: inkMuted,
      ),
      labelSmall: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: inkMuted,
      ),
    );
  }

  static TextStyle displayStyle({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.1,
        color: color ?? ink,
      );

  static TextStyle headlineStyle({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.1,
        color: color ?? ink,
      );

  static TextStyle sectionLabelStyle({Color? color, bool accent = false}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: color ?? (accent ? accentUrgent : inkMuted),
      );

  static TextStyle statValueStyle({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: color ?? ink,
      );

  static TextStyle titleMediumStyle({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color ?? ink,
      );

  static TextStyle titleSmallStyle({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: color ?? ink,
      );

  static TextStyle bodySmallStyle({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: color ?? inkMuted,
      );

  // ── Sombras ────────────────────────────────────────────────────
  static List<BoxShadow> shadowHero(Color tint) => [
        BoxShadow(
          color: tint.withValues(alpha: 0.32),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> shadowCard({bool elevated = false}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: elevated ? 0.08 : 0.04),
          blurRadius: elevated ? 16 : 10,
          offset: Offset(0, elevated ? 4 : 3),
        ),
      ];
}
