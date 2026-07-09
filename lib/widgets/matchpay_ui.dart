import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import 'shimmer_loading.dart';

/// Punto pequeño con pulso suave (opacidad) para títulos de sección urgentes.
class MatchPayPulsingDot extends StatefulWidget {
  final Color color;

  const MatchPayPulsingDot({super.key, required this.color});

  @override
  State<MatchPayPulsingDot> createState() => _MatchPayPulsingDotState();
}

class _MatchPayPulsingDotState extends State<MatchPayPulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final alpha = 0.35 + t * 0.65;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: alpha),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: alpha * 0.45),
                blurRadius: 3 + t * 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Encabezado de sección estándar MatchPay.
class MatchPaySectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final bool accent;
  /// Punto animado junto al título (opción E: vida en el encabezado, no en bordes).
  final bool pulseDot;

  const MatchPaySectionHeader({
    super.key,
    required this.title,
    this.count,
    this.accent = false,
    this.pulseDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = accent
        ? MatchPayTokens.accentUrgent
        : MatchPayTokens.accentCredit;

    return Row(
      children: [
        if (pulseDot) ...[
          MatchPayPulsingDot(color: dotColor),
          const SizedBox(width: 8),
        ],
        Text(
          title.toUpperCase(),
          style: MatchPayTokens.sectionLabelStyle(accent: accent),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: MatchPayTokens.accentUrgentBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: MatchPayTokens.statValueStyle(
                color: MatchPayTokens.accentUrgent,
              ).copyWith(fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}

/// Banner informativo reutilizable.
class MatchPayStatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool urgent;

  const MatchPayStatusBanner({
    super.key,
    required this.icon,
    required this.message,
    this.urgent = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
        urgent ? MatchPayTokens.accentUrgentBg : MatchPayTokens.accentSuccessBg;
    final border = urgent
        ? MatchPayTokens.accentUrgentBorder
        : MatchPayTokens.accentSuccess;
    final fg =
        urgent ? MatchPayTokens.accentUrgent : MatchPayTokens.accentSuccess;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        border: Border.all(color: border.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: MatchPayTokens.bodySmallStyle(color: fg).copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escala sutil al tocar.
class MatchPayTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const MatchPayTapScale({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<MatchPayTapScale> createState() => _MatchPayTapScaleState();
}

class _MatchPayTapScaleState extends State<MatchPayTapScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final child = AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: widget.child,
    );

    if (widget.onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: _setPressed,
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        child: child,
      ),
    );
  }
}

/// Tarjeta blanca con borde y sombra suave.
class MatchPaySurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final bool urgent;
  final VoidCallback? onTap;

  const MatchPaySurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.elevated = false,
    this.urgent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: MatchPayTokens.surfaceCard,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        border: Border.all(
          color: urgent
              ? MatchPayTokens.accentUrgentBorder
              : MatchPayTokens.borderSubtle,
          width: urgent ? 1.5 : 1,
        ),
        boxShadow: MatchPayTokens.shadowCard(elevated: elevated || urgent),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        child: content,
      ),
    );
  }
}

/// Chip de métrica para tiras horizontales de stats.
class MatchPayStatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final double? width;
  final Color? borderColor;

  const MatchPayStatChip({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.width = 136,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 108,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MatchPayTokens.surfaceCard,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        border: Border.all(
          color: borderColor ?? MatchPayTokens.borderSubtle,
          width: borderColor != null ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: MatchPayTokens.statValueStyle(),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MatchPayTokens.sectionLabelStyle().copyWith(
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w500,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton de carga para el home del jugador.
class PlayerHomeShimmer extends StatelessWidget {
  const PlayerHomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  ShimmerLoading(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLoading(
                          width: 160,
                          height: 22,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 8),
                        ShimmerLoading(
                          width: 120,
                          height: 14,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              ShimmerLoading(
                height: 200,
                borderRadius:
                    BorderRadius.circular(MatchPayTokens.radiusHero),
              ),
              const SizedBox(height: 20),
              ShimmerLoading(
                height: 140,
                borderRadius:
                    BorderRadius.circular(MatchPayTokens.radiusCard),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 108,
                child: Row(
                  children: [
                    Expanded(
                      child: ShimmerLoading(
                        borderRadius: BorderRadius.circular(
                          MatchPayTokens.radiusCardSm,
                        ),
                        height: 108,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ShimmerLoading(
                        borderRadius: BorderRadius.circular(
                          MatchPayTokens.radiusCardSm,
                        ),
                        height: 108,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Fila de feature para onboarding / listas informativas.
class MatchPayFeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const MatchPayFeatureRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return MatchPaySurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MatchPayTokens.titleMediumStyle()),
                const SizedBox(height: 4),
                Text(subtitle, style: MatchPayTokens.bodySmallStyle()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
