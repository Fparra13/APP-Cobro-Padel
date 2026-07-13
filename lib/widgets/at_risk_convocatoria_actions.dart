import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/convocatoria_cupo_actions.dart';
import '../utils/matchpay_context.dart';

/// Botones reprogramar / cancelar (cupo imposible / sin resolver) en hero oscuro.
class AtRiskConvocatoriaActions extends StatelessWidget {
  final int partidoId;
  final VoidCallback? onCompleted;
  final Future<void> Function(int partidoId)? reprogramarOverride;
  final Future<void> Function(int partidoId)? cancelarOverride;

  /// Si es false, Reprogramar va como outlined (p. ej. bajo «Marcar como jugado»).
  final bool rescheduleFilled;

  /// Textos opcionales (por defecto: claves at-risk).
  final String? rescheduleLabel;
  final String? cancelLabel;

  const AtRiskConvocatoriaActions({
    super.key,
    required this.partidoId,
    this.onCompleted,
    this.reprogramarOverride,
    this.cancelarOverride,
    this.rescheduleFilled = true,
    this.rescheduleLabel,
    this.cancelLabel,
  });

  void _reprogramar() {
    if (reprogramarOverride != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reprogramarOverride!(partidoId);
      });
      return;
    }
    ConvocatoriaCupoActions.scheduleReprogramar(
      partidoId,
      onSuccess: onCompleted,
    );
  }

  void _cancelar() {
    if (cancelarOverride != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        cancelarOverride!(partidoId);
      });
      return;
    }
    ConvocatoriaCupoActions.scheduleCancelar(
      partidoId,
      onSuccess: onCompleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroActionButton(
          label: rescheduleLabel ?? l10n.tr('organizerCycleAtRiskReschedule'),
          icon: Icons.event_repeat_rounded,
          filled: rescheduleFilled,
          foreground:
              rescheduleFilled ? palette.primaryDark : Colors.white,
          background: rescheduleFilled ? Colors.white : null,
          border: rescheduleFilled
              ? null
              : Colors.white.withValues(alpha: 0.55),
          onActivate: _reprogramar,
        ),
        const SizedBox(height: 8),
        _HeroActionButton(
          label: cancelLabel ?? l10n.tr('organizerCycleAtRiskCancel'),
          icon: Icons.close_rounded,
          filled: false,
          foreground: Colors.white,
          border: Colors.white.withValues(alpha: 0.55),
          onActivate: _cancelar,
        ),
      ],
    );
  }
}

class _HeroActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final Color foreground;
  final Color? background;
  final Color? border;
  final VoidCallback onActivate;

  const _HeroActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.foreground,
    this.background,
    this.border,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
    );

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    if (filled) {
      return FilledButton(
        onPressed: onActivate,
        style: FilledButton.styleFrom(
          backgroundColor: background ?? Colors.white,
          foregroundColor: foreground,
          minimumSize: const Size.fromHeight(44),
          elevation: 0,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onActivate,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: border ?? foreground),
        minimumSize: const Size.fromHeight(44),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: child,
    );
  }
}
