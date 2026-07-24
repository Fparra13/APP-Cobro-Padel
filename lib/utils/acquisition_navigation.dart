import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/acquisition_controller.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../screens/responder_convocatoria_screen.dart';
import '../utils/app_log.dart';

/// Tras login: aplica intención de adquisición (organizer explícito o jugador).
///
/// [MatchPayAcquisitionIntent.createFirstGroup] promueve a organizer y deja
/// [AppUiMode.organizer] para que [RoleAwareShell] muestre Organizer Home.
/// No abre crear encuentro ni paywall: Pro solo al crear (FeatureGate).
Future<void> applyAcquisitionAfterLogin(BuildContext context) async {
  final acq = context.read<AcquisitionController>();
  final settings = context.read<AppSettingsController>();

  switch (acq.intent) {
    case MatchPayAcquisitionIntent.createFirstGroup:
      try {
        if (!AuthService.instance.isOrganizer) {
          await AuthService.instance.becomeOrganizer();
        }
        await AuthService.instance.refreshProfile();
        if (AuthService.instance.isOrganizer) {
          await settings.setUiMode(AppUiMode.organizer);
          // One-shot: limpia intent en [runPendingAcquisitionNavigation].
          // No auto-navega a crear encuentro.
          acq.markPendingOpenOrganizer();
        } else {
          await settings.syncUiModeWithRole(isOrganizer: false);
        }
      } catch (e) {
        appLog('applyAcquisitionAfterLogin createFirstGroup: $e');
        await settings.syncUiModeWithRole(
          isOrganizer: AuthService.instance.isOrganizer,
        );
      }
    case MatchPayAcquisitionIntent.invited:
      await settings.syncUiModeWithRole(
        isOrganizer: AuthService.instance.isOrganizer,
      );
      if (acq.invitePartidoId != null) {
        acq.markPendingOpenInvite();
      }
    case MatchPayAcquisitionIntent.unknown:
      await settings.syncUiModeWithRole(
        isOrganizer: AuthService.instance.isOrganizer,
      );
  }

  await acq.markResolvedAfterLogin();
}

/// Navegación post-login pendiente (invitación).
///
/// createFirstGroup solo consume el flag para no re-aplicar el intent;
/// el usuario ya está en Organizer Home vía [AppUiMode.organizer].
void runPendingAcquisitionNavigation(BuildContext context) {
  final acq = context.read<AcquisitionController>();

  if (acq.consumePendingOpenOrganizer()) {
    return;
  }

  if (!acq.consumePendingOpenInvite()) return;
  final partidoId = acq.consumeInvitePartidoId();
  if (partidoId == null) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ResponderConvocatoriaScreen(partidoId: partidoId),
      ),
    );
  });
}
