import 'package:flutter/material.dart';

import '../l10n/matchpay_strings.dart';
import 'organizer_cycle_hero.dart';

/// Chrome visual del AppBar Attendance (título + toggle detalle).
///
/// No conoce Supabase ni dominio. No muta estado: recibe [showingDetail] y
/// notifica vía [onToggleDetail]. El [Scaffold] del screen sigue siendo dueño
/// del AppBar; este widget es el [PreferredSizeWidget] cuando
/// `surface == attendance`.
class OrganizerAttendanceChrome extends StatelessWidget
    implements PreferredSizeWidget {
  final OrganizerCyclePhase? cyclePhase;
  final bool showingDetail;
  final VoidCallback onToggleDetail;

  /// Fallback de título cuando [cyclePhase] es null (historial / push legacy).
  final bool confirmedFallback;

  final Color backgroundColor;
  final Color foregroundColor;

  /// Acciones del screen (p. ej. eliminar/cancelar), tras el toggle.
  final List<Widget>? actions;

  const OrganizerAttendanceChrome({
    super.key,
    required this.cyclePhase,
    required this.showingDetail,
    required this.onToggleDetail,
    this.confirmedFallback = false,
    required this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  static String titleFor({
    required MatchPayStrings l10n,
    required OrganizerCyclePhase? cyclePhase,
    required bool showingDetail,
    required bool confirmedFallback,
  }) {
    if (showingDetail) return l10n.tr('matchDetailTitle');
    switch (cyclePhase) {
      case OrganizerCyclePhase.confirmed:
        return l10n.tr('organizeMatchConfirmedTitle');
      case OrganizerCyclePhase.atRisk:
        return l10n.tr('organizerCyclePhaseAtRisk');
      case OrganizerCyclePhase.needsResolution:
        return l10n.tr('organizerCyclePhaseNeedsResolution');
      case OrganizerCyclePhase.preparing:
        return l10n.tr('organizeTrackingTitle');
      case OrganizerCyclePhase.empty:
      case OrganizerCyclePhase.registerExpenses:
      case OrganizerCyclePhase.collecting:
      case OrganizerCyclePhase.allPaid:
      case null:
        break;
    }
    if (confirmedFallback) return l10n.tr('organizeMatchConfirmedTitle');
    return l10n.tr('organizeTrackingTitle');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      title: Text(
        titleFor(
          l10n: l10n,
          cyclePhase: cyclePhase,
          showingDetail: showingDetail,
          confirmedFallback: confirmedFallback,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            showingDetail
                ? Icons.fact_check_outlined
                : Icons.info_outline_rounded,
          ),
          tooltip: showingDetail
              ? l10n.tr('organizeTrackingTitle')
              : l10n.tr('asistenciasEditDetails'),
          onPressed: onToggleDetail,
        ),
        ...?actions,
      ],
    );
  }
}
