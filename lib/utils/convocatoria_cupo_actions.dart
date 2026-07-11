import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_repositories.dart';
import '../core/offline_status_controller.dart';
import '../services/notification_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/app_navigation.dart';
import '../utils/matchpay_context.dart';
import '../utils/cancelar_convocatoria_flow.dart';
import '../utils/reprogramar_convocatoria_flow.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';

/// Reprogramar / cancelar convocatoria con cupo imposible (navigator raíz).
class ConvocatoriaCupoActions {
  ConvocatoriaCupoActions._();

  static void scheduleReprogramar(
    int partidoId, {
    VoidCallback? onSuccess,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(reprogramar(partidoId, onSuccess: onSuccess));
    });
  }

  static void scheduleCancelar(
    int partidoId, {
    VoidCallback? onSuccess,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(cancelar(partidoId, onSuccess: onSuccess));
    });
  }

  static BuildContext? get _host => matchPayRootContext;

  static bool _isReadOnly(BuildContext host) {
    try {
      return Provider.of<OfflineStatusController>(host, listen: false).isReadOnly;
    } catch (_) {
      return false;
    }
  }

  static void _snack(
    BuildContext host,
    String message, {
    bool error = false,
  }) {
    final messenger =
        NotificationService.instance.scaffoldMessengerKey?.currentState ??
            ScaffoldMessenger.maybeOf(host);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  static Future<void> reprogramar(
    int partidoId, {
    VoidCallback? onSuccess,
  }) async {
    final host = _host;
    if (host == null || !host.mounted) return;
    if (_isReadOnly(host)) {
      _snack(host, host.l10n.tr('offlineWriteBlocked'));
      return;
    }
    if (!AppRepositories.isReady) {
      _snack(host, host.l10n.tr('reposUnavailableSnackbar'));
      return;
    }

    final conv = await AppRepositories.I.getConvocatoriaCompleta(partidoId);
    if (conv == null || !host.mounted) return;

    final ok = await ReprogramarConvocatoriaFlow.ejecutar(
      host,
      convocatoria: conv,
    );
    if (!ok || !host.mounted) return;

    AppRepositories.notifyDataChanged();
    onSuccess?.call();
  }

  static Future<void> cancelar(
    int partidoId, {
    VoidCallback? onSuccess,
  }) async {
    final host = _host;
    if (host == null || !host.mounted) return;
    if (_isReadOnly(host)) {
      _snack(host, host.l10n.tr('offlineWriteBlocked'));
      return;
    }
    if (!AppRepositories.isReady) {
      _snack(host, host.l10n.tr('reposUnavailableSnackbar'));
      return;
    }

    final l10n = host.l10n;
    final ok = await confirmarEliminarPartido(
      host,
      titulo: l10n.tr('organizerCycleCancelConfirmTitle'),
      mensaje: l10n.tr('organizerCycleCancelConfirmBody'),
      confirmLabel: l10n.tr('organizerCycleCancelConfirmAction'),
      consecuencias: [
        l10n.tr('organizerCycleCancelConsequence1'),
        l10n.tr('organizerCycleCancelConsequence2'),
      ],
    );
    if (!ok || !host.mounted) return;

    final conv = await AppRepositories.I.getConvocatoriaCompleta(partidoId);
    final cancelOk = await CancelarConvocatoriaFlow.ejecutar(
      host,
      partidoId: partidoId,
      convocatoria: conv,
    );
    if (!cancelOk || !host.mounted) return;

    _snack(host, l10n.tr('organizerCycleCancelSuccessSnack'));
    onSuccess?.call();
  }
}
