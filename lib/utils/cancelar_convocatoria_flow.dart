import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../services/convocatoria_comunicacion_service.dart';
import '../utils/app_log.dart';

/// Cancela un partido en convocatoria y avisa a titulares en juego
/// (confirmados + invitados con plazo vigente). No reservas ni rechazados.
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

      // La cancelación en DB es 1 RPC; los avisos no deben bloquear la UI.
      await repos.cancelarConvocatoria(partidoId);
      AppRepositories.notifyDataChanged();

      if (conv != null) {
        unawaited(() async {
          try {
            await ConvocatoriaComunicacionService().avisarCancelacion(conv);
          } catch (e) {
            appLog('Avisos cancelación en background: $e');
          }
        }());
      }
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
