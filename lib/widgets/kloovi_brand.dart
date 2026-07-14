import 'package:flutter/material.dart';

/// Assets oficiales de marca Kloovi.
abstract final class KlooviBrandAssets {
  static const icon = 'assets/brand/icon.png';
  static const wordmark = 'assets/brand/logo-wordmark.png';
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

/// Wordmark (kloovi + tagline). Pensado para fondos blancos.
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

/// Icono + wordmark apilados (onboarding / login).
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
