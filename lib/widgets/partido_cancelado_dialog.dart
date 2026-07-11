import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/matchpay_design_tokens.dart';
import '../core/sport_theme.dart';
import '../l10n/matchpay_strings.dart';
import '../models/mi_convocatoria.dart';
import '../utils/formatters.dart';
import '../widgets/sport_icon.dart';

/// Popup modal cuando el organizador cancela un partido confirmado.
class PartidoCanceladoDialog extends StatefulWidget {
  final MiConvocatoria convocatoria;

  const PartidoCanceladoDialog({super.key, required this.convocatoria});

  static Future<void> show(
    BuildContext context, {
    required MiConvocatoria convocatoria,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return PartidoCanceladoDialog(convocatoria: convocatoria);
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<PartidoCanceladoDialog> createState() => _PartidoCanceladoDialogState();
}

class _PartidoCanceladoDialogState extends State<PartidoCanceladoDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _emojiController;

  @override
  void initState() {
    super.initState();
    _emojiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  void _cerrar() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final partido = widget.convocatoria.partido;
    final palette = SportThemeConfig.paletteFor(partido.sportType);
    final venue = partido.recinto?.trim().isNotEmpty == true
        ? partido.recinto!.trim()
        : '—';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                decoration: BoxDecoration(
                  color: MatchPayTokens.surfaceCard,
                  borderRadius: BorderRadius.circular(MatchPayTokens.radiusHero),
                  border: Border.all(color: MatchPayTokens.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _emojiController,
                      builder: (context, child) {
                        final t = _emojiController.value;
                        final wobble = math.sin(t * math.pi * 2) * 0.04;
                        return Transform.rotate(
                          angle: wobble,
                          child: Transform.scale(
                            scale: 1 + (t * 0.06),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        '😢',
                        style: const TextStyle(fontSize: 56, height: 1),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.tr('playerCancelPopupTitle'),
                      textAlign: TextAlign.center,
                      style: MatchPayTokens.headlineStyle(),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.tr(
                        'playerCancelPopupBody',
                        params: {
                          'date': formatFechaHora(partido.fecha),
                          'venue': venue,
                        },
                      ),
                      textAlign: TextAlign.center,
                      style: MatchPayTokens.bodySmallStyle(
                        color: MatchPayTokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: MatchPayTokens.surfaceInset,
                        borderRadius:
                            BorderRadius.circular(MatchPayTokens.radiusCardSm),
                        border: Border.all(color: MatchPayTokens.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          SportIcon(sport: partido.sportType, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${palette.emoji} ${partido.sportType.labelForLang(context.read<AppSettingsController>().locale.languageCode)}',
                                  style: MatchPayTokens.titleSmallStyle(),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatFechaHora(partido.fecha),
                                  style: MatchPayTokens.bodySmallStyle(),
                                ),
                                if (venue != '—')
                                  Text(
                                    venue,
                                    style: MatchPayTokens.bodySmallStyle(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _cerrar,
                        style: FilledButton.styleFrom(
                          backgroundColor: MatchPayTokens.ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              MatchPayTokens.radiusButton,
                            ),
                          ),
                        ),
                        child: Text(l10n.tr('playerCancelPopupClose')),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: MatchPayTokens.surfaceCard,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _cerrar,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: MatchPayTokens.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
