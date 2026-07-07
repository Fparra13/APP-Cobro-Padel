import 'package:flutter/foundation.dart';

import '../core/app_repositories.dart';
import '../core/supabase_config.dart';
import '../models/jugador.dart';
import '../repositories/jugador_repository_remote.dart';
import '../repositories/partido_repository.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/preferences_service.dart';
import '../services/notification_locale.dart';
import '../services/push_notification_service.dart';
import '../utils/formatters.dart';

class RecordatorioResultado {
  final int enviados;
  final int sinApp;
  final int errores;

  const RecordatorioResultado({
    required this.enviados,
    required this.sinApp,
    required this.errores,
  });
}

class _DatosCobroPrefs {
  final String titular;
  final String banco;
  final String cuenta;

  const _DatosCobroPrefs(this.titular, this.banco, this.cuenta);
}

enum _EnvioRecordatorio { ok, sinApp, error }

/// Recordatorios de deuda vía push FCM (jugadores con la app).
class RecordatorioService {
  final _prefs = PreferencesService();
  final _jugadorRepo = JugadorRepositoryRemote();

  AppRepositories get _repos => AppRepositories.active;

  Future<_DatosCobroPrefs> _loadPrefs() async {
    final data = await Future.wait<String>([
      _prefs.titularNombre,
      _prefs.bancoNombre,
      _prefs.cuentaNumero,
    ]);
    return _DatosCobroPrefs(data[0], data[1], data[2]);
  }

  Future<String> construirMensaje({
    required Jugador jugador,
    required double saldo,
    bool detallado = true,
  }) async {
    final prefs = await _loadPrefs();
    final partidos = await _repos.getPartidosPendientesJugador(
      jugador.keyId,
      reconciliar: false,
    );

    if (detallado && partidos.isNotEmpty) {
      final ultimo = partidos.last;
      final completo = await _repos.getPartidoCompleto(ultimo.partidoId);
      if (completo != null) {
        final desgloseList = await _repos.getDesglose(
          ultimo.partidoId,
          reconciliar: false,
        );
        final d = desgloseList
            .where((x) => x.jugadorKeyId == jugador.keyId)
            .firstOrNull;
        if (d != null) {
          return MensajeCobroService.construirDetallePartido(
            partido: completo.partido,
            desglose: d,
            deudasAnteriores: const [],
            titular: prefs.titular,
            banco: prefs.banco,
            cuenta: prefs.cuenta,
          );
        }
      }
    }

    return MensajeCobroService.construirRecordatorio(
      nombreJugador: jugador.nombre,
      saldo: saldo,
      partidos: partidos,
      titular: prefs.titular,
      banco: prefs.banco,
      cuenta: prefs.cuenta,
    );
  }

  Future<String?> _resolverTargetId(Jugador jugador) async {
    final email = jugador.contactEmail;
    if (email != null && email.isNotEmpty) {
      final porEmail = await _jugadorRepo.getByEmail(email);
      if (porEmail?.supabaseId != null && porEmail!.supabaseId!.isNotEmpty) {
        return porEmail.supabaseId;
      }
    }
    return jugador.supabaseId ?? (jugador.keyId.isNotEmpty ? jugador.keyId : null);
  }

  Future<void> enviarIndividual({
    required Jugador jugador,
    required double saldo,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw Exception('Requiere conexión a Supabase');
    }

    final targetId = await _resolverTargetId(jugador);
    if (targetId == null || targetId.isEmpty) {
      throw Exception(
        '${jugador.nombre} no tiene perfil en la app. '
        'Usa "Copiar mensaje" para enviar manualmente.',
      );
    }

    await _enviarPushRapido(
      jugador: jugador,
      saldo: saldo,
      targetId: targetId,
    );
  }

  Future<void> _enviarPushRapido({
    required Jugador jugador,
    required double saldo,
    required String targetId,
    _DatosCobroPrefs? prefsCache,
  }) async {
    final prefs = prefsCache ?? await _loadPrefs();
    final partidos = await _repos.getPartidosPendientesJugador(
      jugador.keyId,
      reconciliar: false,
    );
    final cuerpo = MensajeCobroService.construirRecordatorio(
      nombreJugador: jugador.nombre,
      saldo: saldo,
      partidos: partidos,
      titular: prefs.titular,
      banco: prefs.banco,
      cuenta: prefs.cuenta,
    );
    final resumen =
        cuerpo.length > 180 ? '${cuerpo.substring(0, 177)}…' : cuerpo;
    final lang = await NotificationLocale.forUser(targetId);

    await PushNotificationService.instance.enviar(
      userIds: [targetId],
      title: NotificationLocale.tr(
        lang,
        'notifPaymentReminderTitle',
        params: {'amount': formatMoney(saldo)},
      ),
      body: resumen,
      data: const {'type': 'cobro_partido', 'partido_id': '0'},
    );
  }

  Future<RecordatorioResultado> enviarATodos(
    List<ResumenJugador> resumenes,
  ) async {
    final deudores = resumenes.where((r) => r.tieneDeuda).toList();
    if (deudores.isEmpty) {
      return const RecordatorioResultado(
        enviados: 0,
        sinApp: 0,
        errores: 0,
      );
    }

    final prefs = await _loadPrefs();
    var enviados = 0;
    var sinApp = 0;
    var errores = 0;

    final outcomes = await Future.wait(
      deudores.map((r) async {
        try {
          final targetId = await _resolverTargetId(r.jugador);
          if (targetId == null || targetId.isEmpty) {
            return _EnvioRecordatorio.sinApp;
          }
          await _enviarPushRapido(
            jugador: r.jugador,
            saldo: r.deudaVisible,
            targetId: targetId,
            prefsCache: prefs,
          );
          return _EnvioRecordatorio.ok;
        } catch (e) {
          debugPrint('Recordatorio ${r.jugador.nombre}: $e');
          if (e.toString().contains('no tiene perfil')) {
            return _EnvioRecordatorio.sinApp;
          }
          return _EnvioRecordatorio.error;
        }
      }),
    );

    for (final o in outcomes) {
      switch (o) {
        case _EnvioRecordatorio.ok:
          enviados++;
        case _EnvioRecordatorio.sinApp:
          sinApp++;
        case _EnvioRecordatorio.error:
          errores++;
      }
    }

    return RecordatorioResultado(
      enviados: enviados,
      sinApp: sinApp,
      errores: errores,
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
