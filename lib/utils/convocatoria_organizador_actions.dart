import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../utils/cancelar_convocatoria_flow.dart';
import '../utils/matchpay_context.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';

/// Si ya hay al menos un titular confirmado, no se debe hard-delete:
/// hay que cancelar (y avisar). Sin confirmaciones, eliminar es seguro.
bool debeForzarCancelarEnVezDeEliminar(ConvocatoriaCompleta? convocatoria) =>
    (convocatoria?.confirmados ?? 0) > 0;

/// Elimina por completo una convocatoria/partido en organización.
///
/// Si hay confirmaciones, redirige al flujo de cancelación (con aviso).
Future<bool> confirmarYEliminarConvocatoria(
  BuildContext context, {
  required int partidoId,
  ConvocatoriaCompleta? convocatoria,
}) async {
  final l10n = context.l10n;
  final repos =
      AppRepositories.isReady ? AppRepositories.I : context.repos;

  ConvocatoriaCompleta? conv = convocatoria;
  try {
    conv ??= await repos.getConvocatoriaCompleta(partidoId);
  } catch (_) {
    // Si no se puede refrescar, usamos el snapshot en memoria (si existe).
  }

  if (debeForzarCancelarEnVezDeEliminar(conv)) {
    return _confirmarYCancelarPorConfirmados(
      context,
      partidoId: partidoId,
      convocatoria: conv,
    );
  }

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

Future<bool> _confirmarYCancelarPorConfirmados(
  BuildContext context, {
  required int partidoId,
  ConvocatoriaCompleta? convocatoria,
}) async {
  final l10n = context.l10n;
  final n = convocatoria?.confirmados ?? 0;
  final ok = await confirmarEliminarPartido(
    context,
    titulo: l10n.tr('organizerCycleCancelConfirmTitle'),
    mensaje: l10n.tr(
      'organizeDeleteRedirectCancelBody',
      params: {'count': '$n'},
    ),
    confirmLabel: l10n.tr('organizerCycleCancelConfirmAction'),
    consecuencias: [
      l10n.tr('organizeDeleteRedirectCancelConsequence1'),
      l10n.tr('organizerCycleCancelConsequence1'),
      l10n.tr('organizerCycleCancelConsequence2'),
    ],
  );
  if (!ok || !context.mounted) return false;

  final cancelOk = await CancelarConvocatoriaFlow.ejecutar(
    context,
    partidoId: partidoId,
    convocatoria: convocatoria,
  );
  if (cancelOk && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('organizerCycleCancelSuccessSnack'))),
    );
  }
  return cancelOk;
}
