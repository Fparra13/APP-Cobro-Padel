import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../models/mi_convocatoria.dart';
import '../services/cancelacion_vista_service.dart';
import '../widgets/partido_cancelado_dialog.dart';

AppRepositories _reposFor(BuildContext context) =>
    AppRepositories.isReady ? AppRepositories.I : AppRepositoriesScope.of(context);

/// Muestra popups de partidos cancelados no vistos por el jugador.
class PartidoCanceladoPopupFlow {
  PartidoCanceladoPopupFlow._();

  static Future<void> mostrarPendientesEnHome(BuildContext context) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || !context.mounted) return;

    final repos = _reposFor(context);
    if (!repos.isCloud) return;

    List<MiConvocatoria> cancelaciones;
    try {
      cancelaciones = await repos.getCancelacionesJugadorPendientes();
    } catch (_) {
      return;
    }
    if (!context.mounted) return;

    await _mostrarFiltradas(context, userId: userId, cancelaciones: cancelaciones);
  }

  static Future<void> mostrarPartido(
    BuildContext context, {
    required int partidoId,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || !context.mounted) return;

    final yaVista = await CancelacionVistaService.filtrarNoVistas(
      userId: userId,
      partidoIds: [partidoId],
    );
    if (yaVista.isEmpty) return;
    if (!context.mounted) return;

    final repos = _reposFor(context);
    MiConvocatoria? conv;
    try {
      // Solo si el servidor aún la considera pendiente (sobrevive reinstall).
      conv = await repos.getCancelacionJugadorPendiente(partidoId);
    } catch (_) {
      return;
    }
    if (conv == null || !context.mounted) return;

    await PartidoCanceladoDialog.show(context, convocatoria: conv);
    await CancelacionVistaService.marcarVista(
      userId: userId,
      partidoId: partidoId,
    );
  }

  static Future<void> _mostrarFiltradas(
    BuildContext context, {
    required String userId,
    required List<MiConvocatoria> cancelaciones,
  }) async {
    final ids = cancelaciones
        .map((c) => c.partido.id)
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return;

    final pendientes = await CancelacionVistaService.filtrarNoVistas(
      userId: userId,
      partidoIds: ids,
    );
    if (pendientes.isEmpty || !context.mounted) return;

    final porId = {
      for (final c in cancelaciones)
        if (c.partido.id != null) c.partido.id!: c,
    };

    for (final partidoId in pendientes) {
      final conv = porId[partidoId];
      if (conv == null || !context.mounted) continue;
      await PartidoCanceladoDialog.show(context, convocatoria: conv);
      await CancelacionVistaService.marcarVista(
        userId: userId,
        partidoId: partidoId,
      );
    }
  }
}
