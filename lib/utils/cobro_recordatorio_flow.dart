import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/cobro_recordatorio_prefs.dart';
import '../services/preferences_service.dart';

/// Diálogo post-cobro: activar o no recordatorios automáticos del partido.
class CobroRecordatorioPartidoFlow {
  CobroRecordatorioPartidoFlow._();

  /// Muestra el diálogo y llama a [generarRecordatoriosPartido].
  /// No bloquea ni falla el registro del partido si el RPC falla.
  static Future<void> preguntarTrasRegistrarCobros(
    BuildContext context, {
    required int partidoId,
  }) async {
    if (!AppRepositories.isReady || !context.mounted) return;

    final l10n = context.l10n;
    final activar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('autoRemindersDialogTitle')),
        content: Text(l10n.tr('autoRemindersDialogBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('autoRemindersDialogNotNow')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('autoRemindersDialogActivate')),
          ),
        ],
      ),
    );

    if (activar == null || !context.mounted) return;

    try {
      final result = await AppRepositories.I.generarRecordatoriosPartido(
        partidoId: partidoId,
        generar: activar,
      );
      if (!context.mounted) return;

      if (activar && !result.prefsActivo) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tr('autoRemindersPrefsOffSnack')),
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (activar && result.creados > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('autoRemindersEnabledSnack'))),
        );
      }
    } catch (_) {
      // El partido ya quedó registrado; no spamear error de recordatorios.
    }
  }
}

/// Carga prefs remotas + migración one-shot desde SharedPreferences.
class CobroRecordatorioPrefsLoader {
  CobroRecordatorioPrefsLoader._();

  static Future<String> deviceTimezone() async {
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      if (name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return 'America/Santiago';
  }

  static Future<CobroRecordatorioPrefs> loadAndMigrateIfNeeded() async {
    if (!AppRepositories.isReady) {
      return CobroRecordatorioPrefs.defaults;
    }

    final remote = await AppRepositories.I.getCobroRecordatorioPrefs();
    final localPrefs = PreferencesService();

    if (remote.exists) {
      await localPrefs.markRecordatorioMigrated();
      return remote;
    }

    final already = await localPrefs.recordatorioMigrated;
    if (already) return remote;

    final localActivo = await localPrefs.recordatorioActivo;
    final localDias = await localPrefs.recordatorioDias;
    final hora = await localPrefs.recordatorioHora;
    final minuto = await localPrefs.recordatorioMinuto;
    final tz = await deviceTimezone();

    // Mapear días locales a opciones V1 más cercanas.
    final diasPrimer =
        CobroRecordatorioPrefs.normalizePrimer(localDias);
    const frecuencia = 3;

    final migrated = CobroRecordatorioPrefs(
      activo: localActivo,
      diasPrimer: diasPrimer,
      frecuenciaDias: frecuencia,
      horaLocal: TimeOfDayLike(hour: hora, minute: minuto),
      timezone: tz,
      exists: true,
    );

    if (localActivo ||
        await localPrefs.recordatorioDias != 3 ||
        hora != 10 ||
        minuto != 0) {
      final saved = await AppRepositories.I.upsertCobroRecordatorioPrefs(migrated);
      await localPrefs.markRecordatorioMigrated();
      await localPrefs.clearRecordatorioLocal();
      return saved;
    }

    await localPrefs.markRecordatorioMigrated();
    return remote;
  }
}
