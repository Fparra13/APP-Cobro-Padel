import 'package:flutter/foundation.dart';

import '../core/app_repositories.dart';
import '../core/supabase_config.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/datos_pago_organizador.dart';
import '../models/jugador.dart';
import '../repositories/jugador_repository_remote.dart';
import '../repositories/partido_repository.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/preferences_service.dart';
import '../services/notification_locale.dart';
import '../services/push_notification_service.dart';
import '../utils/formatters.dart';
import '../utils/app_log.dart';

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

enum _EnvioRecordatorio { ok, sinApp, error }

/// Recordatorios de deuda vía push FCM (jugadores con la app).
class RecordatorioService {
  final _prefs = PreferencesService();
  final _jugadorRepo = JugadorRepositoryRemote();

  Future<String> construirMensaje({
    required Jugador jugador,
    required double saldo,
    bool detallado = true,
  }) async {
    final pago = await _prefs.datosPago;
    final repos = AppRepositories.tryActive;
    final partidos = repos == null
        ? <DeudaPartidoAnterior>[]
        : await repos.getPartidosPendientesJugador(
            jugador.keyId,
            reconciliar: false,
          );

    if (detallado && partidos.isNotEmpty && repos != null) {
      final ultimo = partidos.last;
      final completo = await repos.getPartidoCompleto(ultimo.partidoId);
      if (completo != null) {
        final desgloseList = await repos.getDesglose(
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
            pago: pago,
          );
        }
      }
    }

    return MensajeCobroService.construirRecordatorio(
      nombreJugador: jugador.nombre,
      saldo: saldo,
      partidos: partidos,
      pago: pago,
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
    if (!SupabaseConfig.isConfigured || AppRepositories.tryActive == null) {
      throw const AppRepositoriesUnavailable();
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
    DatosPagoOrganizador? pagoCache,
  }) async {
    final pago = pagoCache ?? await _prefs.datosPago;
    final repos = AppRepositories.tryActive;
    final partidos = repos == null
        ? <DeudaPartidoAnterior>[]
        : await repos.getPartidosPendientesJugador(
            jugador.keyId,
            reconciliar: false,
          );
    final detalle = MensajeCobroService.construirRecordatorio(
      nombreJugador: jugador.nombre,
      saldo: saldo,
      partidos: partidos,
      pago: pago,
    );
    final lang = await NotificationLocale.forUser(targetId);
    final cuerpo = NotificationLocale.tr(
      lang,
      'notifPaymentReminderBodyShort',
      params: {'amount': formatMoney(saldo)},
    );

    await PushNotificationService.instance.enviar(
      userIds: [targetId],
      title: NotificationLocale.tr(
        lang,
        'notifPaymentReminderTitle',
        params: {'amount': formatMoney(saldo)},
      ),
      body: cuerpo,
      data: {
        'type': 'cobro_partido',
        'partido_id': '0',
        'detalle': detalle.length > 900
            ? '${detalle.substring(0, 897)}…'
            : detalle,
      },
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

    final pago = await _prefs.datosPago;
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
            pagoCache: pago,
          );
          return _EnvioRecordatorio.ok;
        } catch (e) {
          appLog('Recordatorio falló para un jugador');
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
