import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';

/// Assets oficiales de marca Kloovi.
abstract final class KlooviBrandAssets {
  static const icon = 'assets/brand/icon.png';

  /// Wordmark sin slogan (homes Organizador / Participante).
  static const wordmark = 'assets/brand/logo-wordmark.png';

  static const splashEs = 'assets/brand/logo-splash-es.png';
  static const splashEn = 'assets/brand/logo-splash-en.png';
  static const splashPt = 'assets/brand/logo-splash-pt.png';

  /// Código de idioma de marca (`es` / `en` / `pt`), alineado a TranslationMaps.
  static String brandLanguageCode(Locale locale) {
    switch (locale.languageCode.toLowerCase()) {
      case 'en':
        return 'en';
      case 'pt':
        return 'pt';
      case 'es':
        return 'es';
      default:
        return 'es';
    }
  }

  /// Splash / login según idioma activo.
  static String splashForLanguage(String languageCode) {
    switch (brandLanguageCode(Locale(languageCode))) {
      case 'en':
        return splashEn;
      case 'pt':
        return splashPt;
      case 'es':
      default:
        return splashEs;
    }
  }

  static String splashForLocale(Locale locale) =>
      splashForLanguage(brandLanguageCode(locale));
}

/// Icono de app (squircle teal + símbolo blanco).
class KlooviIcon extends StatelessWidget {
  final double size;
  final BorderRadius? borderRadius;

  const KlooviIcon({
    super.key,
    this.size = 72,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(size * 0.22),
      child: Image.asset(
        KlooviBrandAssets.icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Kloovi',
      ),
    );
  }
}

/// Wordmark de app (sin slogan embebido). Fondos claros.
class KlooviWordmark extends StatelessWidget {
  final double height;
  final double? maxWidth;

  const KlooviWordmark({
    super.key,
    this.height = 56,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      KlooviBrandAssets.wordmark,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Kloovi',
    );
    if (maxWidth == null) return image;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: image,
    );
  }
}

/// Logo de splash / login (wordmark + tagline localizado en el asset).
class KlooviSplashLogo extends StatelessWidget {
  final double height;
  final double? maxWidth;

  const KlooviSplashLogo({
    super.key,
    this.height = 120,
    this.maxWidth = 320,
  });

  @override
  Widget build(BuildContext context) {
    // Misma fuente que el resto de la UI (preferencia), no el locale del SO.
    final settings = context.watch<AppSettingsController>();
    final locale = AppSettingsController.normalizePickerLocale(settings.locale);
    final lang = KlooviBrandAssets.brandLanguageCode(locale);
    final asset = KlooviBrandAssets.splashForLanguage(lang);

    final image = ColoredBox(
      color: Colors.white,
      child: Image.asset(
        asset,
        key: ValueKey('splash-$lang-$asset'),
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Kloovi',
      ),
    );
    if (maxWidth == null) return image;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: image,
    );
  }
}

/// Wordmark + slogan de rol (Organizador / Participante).
class KlooviHomeBrand extends StatelessWidget {
  final bool forOrganizer;
  final double wordmarkHeight;
  final double? maxWidth;

  const KlooviHomeBrand({
    super.key,
    required this.forOrganizer,
    this.wordmarkHeight = 40,
    this.maxWidth = 210,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slogan = l10n.tr(
      forOrganizer ? 'brandTaglineOrganizer' : 'brandTaglinePlayer',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        KlooviWordmark(height: wordmarkHeight, maxWidth: maxWidth),
        const SizedBox(height: 4),
        Text(
          slogan,
          style: MatchPayTokens.bodySmallStyle().copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: MatchPayTokens.inkMuted,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Header de onboarding: icono + wordmark (sin slogan de splash).
class KlooviBrandHeader extends StatelessWidget {
  final double iconSize;
  final double wordmarkHeight;
  final double gap;

  const KlooviBrandHeader({
    super.key,
    this.iconSize = 88,
    this.wordmarkHeight = 64,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KlooviIcon(size: iconSize),
        SizedBox(height: gap),
        KlooviWordmark(height: wordmarkHeight, maxWidth: 280),
      ],
    );
  }
}
