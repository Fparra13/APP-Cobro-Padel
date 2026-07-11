import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../services/convocatoria_comunicacion_service.dart';
import '../utils/formatters.dart';
import '../utils/app_navigation.dart';
import '../widgets/convocatoria_whatsapp_sin_app_sheet.dart';

/// Reprograma un partido y avisa automáticamente a titulares (push + WhatsApp sin app).
class ReprogramarConvocatoriaFlow {
  ReprogramarConvocatoriaFlow._();

  static Future<bool> ejecutar(
    BuildContext context, {
    required ConvocatoriaCompleta convocatoria,
    DateTime? fechaInicial,
  }) async {
    final host = matchPayRootContext ?? context;
    if (!host.mounted) return false;

    final partidoId = convocatoria.partido.id;
    if (partidoId == null) return false;

    final nuevaFecha = await _elegirFechaHora(
      host,
      convocatoria: convocatoria,
      fechaInicial: fechaInicial,
    );
    if (nuevaFecha == null || !host.mounted) return false;

    try {
      final repos = AppRepositories.isReady
          ? AppRepositories.I
          : host.repos;
      await repos.reprogramarConvocatoria(
        partidoId: partidoId,
        nuevaFecha: nuevaFecha,
      );
      final fresh = await repos.getConvocatoriaCompleta(partidoId);
      if (!host.mounted) return false;

      final convParaAviso = fresh ??
          ConvocatoriaCompleta(
            partido: convocatoria.partido.copyWith(
              fecha: nuevaFecha,
              estado: EstadoPartido.organizando,
              reprogramadoEn: DateTime.now(),
              clearResueltoEn: true,
            ),
            jugadores: convocatoria.jugadores,
          );

      final result = await ConvocatoriaComunicacionService()
          .avisarReprogramacion(convParaAviso);
      AppRepositories.notifyDataChanged();

      if (result.sinApp.isNotEmpty && host.mounted) {
        final estados = {
          for (final e in convParaAviso.titulares)
            e.jugador.keyId: e.estado,
        };
        await ConvocatoriaWhatsAppSinAppSheet.show(
          host,
          partidoId: partidoId,
          jugadores: result.sinApp,
          estados: estados,
        );
      }

      if (host.mounted) {
        ScaffoldMessenger.of(host).showSnackBar(
          SnackBar(
            content: Text(
              host.l10n.tr(
                'reprogramSuccessSnack',
                params: {
                  'push': '${result.pushEnviados}',
                  'whatsapp': '${result.sinApp.length}',
                },
              ),
            ),
          ),
        );
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

  static Future<bool> recordarPendientes(
    BuildContext context, {
    required ConvocatoriaCompleta convocatoria,
  }) async {
    final partidoId = convocatoria.partido.id;
    if (partidoId == null) return false;

    try {
      final repos = AppRepositories.isReady
          ? AppRepositories.I
          : context.repos;
      final fresh =
          await repos.getConvocatoriaCompleta(partidoId) ?? convocatoria;
      final result =
          await ConvocatoriaComunicacionService().recordarPendientes(fresh);

      if (result.pushEnviados == 0 && result.sinApp.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.tr('remindPendingNoneSnack')),
            ),
          );
        }
        return false;
      }

      if (result.sinApp.isNotEmpty && context.mounted) {
        final estados = {
          for (final e in fresh.titulares)
            e.jugador.keyId: e.estado,
        };
        await ConvocatoriaWhatsAppSinAppSheet.show(
          context,
          partidoId: partidoId,
          jugadores: result.sinApp,
          estados: estados,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr(
                'remindPendingSuccessSnack',
                params: {'count': '${result.pushEnviados + result.sinApp.length}'},
              ),
            ),
          ),
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

  static Future<DateTime?> _elegirFechaHora(
    BuildContext context, {
    required ConvocatoriaCompleta convocatoria,
    DateTime? fechaInicial,
  }) async {
    final l10n = context.l10n;
    final sugerida = fechaInicial ??
        (convocatoria.partido.fecha.isAfter(DateTime.now())
            ? convocatoria.partido.fecha
            : DateTime.now().add(const Duration(days: 1)));

    final fecha = await showDatePicker(
      context: context,
      useRootNavigator: true,
      initialDate: sugerida,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: Localizations.localeOf(context),
      helpText: l10n.tr('reprogramPickDateTitle'),
    );
    if (fecha == null || !context.mounted) return null;

    final hora = await showTimePicker(
      context: context,
      useRootNavigator: true,
      initialTime: TimeOfDay.fromDateTime(sugerida),
      helpText: l10n.tr('reprogramPickTimeTitle'),
    );
    if (hora == null || !context.mounted) return null;

    final nueva = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      hora.hour,
      hora.minute,
    );
    if (!nueva.isAfter(DateTime.now())) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tr('organizerCycleRescheduleFutureError')),
          ),
        );
      }
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_repeat_rounded),
        title: Text(l10n.tr('reprogramConfirmTitle')),
        content: Text(
          l10n.tr(
            'reprogramConfirmBody',
            params: {'date': formatDiaCompleto(nueva)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('reprogramConfirmAction')),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return nueva;
  }
}
