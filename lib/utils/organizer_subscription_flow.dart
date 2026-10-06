import 'package:flutter/material.dart';

import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Flujo para convertirse en Organizer (rol gratuito).
///
/// No exige Pro, no abre paywall y no inicia trial.
/// Crear nuevos encuentros sigue requiriendo Pro en
/// [abrirOrganizarPartido] / [abrirNuevoPartidoJugado].
Future<void> openOrganizerSubscriptionFlow(BuildContext context) async {
  if (AuthService.instance.isOrganizer) {
    await context.switchAppUiMode(AppUiMode.organizer);
    return;
  }

  try {
    await AuthService.instance.becomeOrganizer();
    await AuthService.instance.refreshProfile();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.userError(e))),
    );
    return;
  }
  if (!context.mounted) return;
  await context.switchAppUiMode(AppUiMode.organizer);
}
