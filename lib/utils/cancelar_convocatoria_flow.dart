import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../services/convocatoria_comunicacion_service.dart';

/// Cancela un partido en convocatoria y avisa solo a titulares confirmados.
class CancelarConvocatoriaFlow {
  CancelarConvocatoriaFlow._();

  static Future<bool> ejecutar(
    BuildContext context, {
    required int partidoId,
    ConvocatoriaCompleta? convocatoria,
  }) async {
    final host = context;
    if (!host.mounted) return false;

    try {
      final repos = AppRepositories.isReady
          ? AppRepositories.I
          : host.repos;
      final conv =
          convocatoria ?? await repos.getConvocatoriaCompleta(partidoId);
      if (conv == null) {
        await repos.cancelarConvocatoria(partidoId);
        AppRepositories.notifyDataChanged();
        return true;
      }

      await repos.cancelarConvocatoria(partidoId);
      await ConvocatoriaComunicacionService().avisarCancelacion(conv);
      AppRepositories.notifyDataChanged();
      return true;
    } catch (e) {
      if (host.mounted) {
        ScaffoldMessenger.of(host).showSnackBar(
          SnackBar(
            content: Text(host.userError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    }
  }
}
