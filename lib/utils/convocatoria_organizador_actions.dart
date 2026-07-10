import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../utils/matchpay_context.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';

/// Elimina por completo una convocatoria/partido en organización.
Future<bool> confirmarYEliminarConvocatoria(
  BuildContext context, {
  required int partidoId,
  ConvocatoriaCompleta? convocatoria,
}) async {
  final l10n = context.l10n;
  final ok = await confirmarEliminarPartido(
    context,
    titulo: l10n.tr('organizeDeleteInviteTitle'),
    mensaje: l10n.tr('organizeDeleteInviteMessage'),
    consecuencias: [
      l10n.tr('organizeDeleteInviteConsequence1'),
      l10n.tr('organizeDeleteInviteConsequence2'),
      l10n.tr('organizeDeleteInviteConsequence3'),
    ],
  );
  if (!ok || !context.mounted) return false;

  try {
    final repos =
        AppRepositories.isReady ? AppRepositories.I : context.repos;
    await repos.eliminarConvocatoria(partidoId);
    AppRepositories.notifyDataChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('matchDeleted'))),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.userError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    return false;
  }
}
