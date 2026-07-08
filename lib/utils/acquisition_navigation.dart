import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/acquisition_controller.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../screens/responder_convocatoria_screen.dart';
import '../utils/app_navigation.dart';

/// Tras login: aplica intención de adquisición (organizer explícito o jugador).
Future<void> applyAcquisitionAfterLogin(BuildContext context) async {
  final acq = context.read<AcquisitionController>();
  final settings = context.read<AppSettingsController>();

  switch (acq.intent) {
    case MatchPayAcquisitionIntent.createFirstGroup:
      if (!AuthService.instance.isOrganizer) {
        await AuthService.instance.becomeOrganizer();
      }
      await settings.setUiMode(AppUiMode.organizer);
      acq.markPendingOpenOrganizer();
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

/// Abre convocatoria o flujo de primer grupo si quedó pendiente tras login.
void runPendingAcquisitionNavigation(BuildContext context) {
  final acq = context.read<AcquisitionController>();

  if (acq.consumePendingOpenOrganizer()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(abrirOrganizarPartido(context));
    });
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
