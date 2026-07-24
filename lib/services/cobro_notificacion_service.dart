import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import '../domain/cobro_notificacion_logic.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/partido.dart';
import '../repositories/jugador_repository_remote.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/notification_locale.dart';
import '../services/notification_service.dart';
import '../services/preferences_service.dart';
import '../services/push_notification_service.dart';
import '../utils/formatters.dart';
import '../utils/app_log.dart';

/// Push de cobros: jugadores reciben detalle; organizador recibe comprobantes.
class CobroNotificacionService {
  final _jugadorRepo = JugadorRepositoryRemote();
  final _prefs = PreferencesService();

  /// Tras registrar cobros del partido, notifica a cada jugador con deuda.
  Future<void> notificarCobrosPartido(int partidoId) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      var enviados = await _notificarCobrosPartidoOnce(partidoId);
      if (enviados == 0) {
        // Snapshot/desglose a veces llegan un instante después del insert.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        enviados = await _notificarCobrosPartidoOnce(partidoId);
      }
      if (enviados == 0) {
        appLog('CobroNotificacion: sin notificaciones en $partidoId');
      } else {
        appLog(
          'CobroNotificacion: $enviados push(es) para partido $partidoId',
        );
      }
    } catch (e, st) {
      appLog('CobroNotificacionService.notificarCobrosPartido: $e\n$st');
    }
  }

  Future<int> _notificarCobrosPartidoOnce(int partidoId) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final repos = AppRepositories.tryActive;
    if (repos == null) {
      appLog('CobroNotificacion: AppRepositories.tryActive es null');
      return 0;
    }

    final completo = await repos.getPartidoCompleto(partidoId);
    if (completo == null) {
      appLog('CobroNotificacion: partido $partidoId no encontrado');
      return 0;
    }

    final desglose = await repos.getDesglose(partidoId, reconciliar: false);
    final desglosePorId = {
      for (final d in desglose)
        if (d.jugadorSupabaseId != null) d.jugadorSupabaseId!: d,
    };

    final pagoLocal = await _prefs.datosPago;
    var pago = pagoLocal;
    final orgId = AuthService.instance.currentUser?.id;
    if (orgId != null && AppRepositories.isReady) {
      try {
        final remote = await repos.getDatosPagoOrganizador(orgId);
        if (remote != null && remote.pago.tieneDatos) {
          pago = remote.pago;
        }
      } catch (_) {}
    }
    final fechaTxt = formatDiaCompleto(completo.partido.fecha);
    final uid = AuthService.instance.currentUser?.id;

    final candidatos = completo.detalles.where((d) {
      return debeNotificarCobroPendiente(
        detalle: d,
        desglose: desglosePorId[d.jugadorSupabaseId],
        snapshotSaldoAnterior: completo.snapshotSaldoCobro(d),
      );
    }).toList();

    if (candidatos.isEmpty) {
      appLog(
        'CobroNotificacion: sin candidatos con deuda en $partidoId '
        '(detalles=${completo.detalles.length}, desglose=${desglose.length})',
      );
    }

    var enviados = 0;
    await Future.wait(
      candidatos.map((det) async {
        final jugadorId = det.jugadorSupabaseId!;
        final d = desglosePorId[jugadorId];
        final snap = completo.snapshotSaldoCobro(det);
        final monto = montoNotificacionCobroPendiente(
          detalle: det,
          desglose: d,
          snapshotSaldoAnterior: snap,
        );
        if (monto <= 0.005) return;

        final targetId = await _resolverIdNotificacion(jugadorId);
        if (targetId.isEmpty) {
          appLog(
            'CobroNotificacion: sin targetId para jugador $jugadorId',
          );
          return;
        }

        final lang = await NotificationLocale.forUser(targetId);
        final titulo = NotificationLocale.tr(lang, 'notifMatchChargeTitle');
        final sportParams = _sportParams(completo.partido.sportType, lang);
        final cuerpo = d != null
            ? _resumenPush(d, completo.partido, fechaTxt, lang)
            : '${sportParams['sportEmoji']} ${sportParams['sport']} · ${NotificationLocale.tr(
                lang,
                'notifMatchChargeBodySimple',
                params: {
                  'date': fechaTxt,
                  'amount': formatMoney(monto),
                },
              )}';

        final detalleTexto = d != null
            ? MensajeCobroService.construirDetallePartido(
                partido: completo.partido,
                desglose: d,
                deudasAnteriores: const [],
                pago: pago,
              )
            : _detalleSimple(completo.partido, det, monto, lang);

        final ok = await _entregarCobroJugador(
          uid: uid,
          targetId: targetId,
          partidoId: partidoId,
          titulo: titulo,
          cuerpo: cuerpo,
          detalleTexto: detalleTexto,
          type: 'cobro_partido',
        );
        if (ok) enviados++;
      }),
    );

    final cubiertosConFavor = completo.detalles.where((d) {
      return debeNotificarCobroCubiertoConFavor(
        detalle: d,
        desglose: desglosePorId[d.jugadorSupabaseId],
        snapshotSaldoAnterior: completo.snapshotSaldoCobro(d),
      );
    }).toList();

    await Future.wait(
      cubiertosConFavor.map((det) async {
        final jugadorId = det.jugadorSupabaseId!;
        final dsg = desglosePorId[jugadorId];
        if (dsg == null) return;
        final targetId = await _resolverIdNotificacion(jugadorId);
        if (targetId.isEmpty) return;

        final lang = await NotificationLocale.forUser(targetId);
        final titulo =
            NotificationLocale.tr(lang, 'notifMatchPaidWithCreditTitle');
        final cuerpo = NotificationLocale.tr(
          lang,
          'notifMatchPaidWithCreditBody',
          params: {
            'matchAmount': formatMoney(dsg.totalPartido),
            'credit': formatMoney(dsg.saldoFavorAplicado),
          },
        );
        final creditoRestante = dsg.saldoRestantePartido < -0.005
            ? -dsg.saldoRestantePartido
            : 0.0;
        final detalleTexto = [
          NotificationLocale.tr(
            lang,
            'notifMatchPaidWithCreditDetail',
            params: {
              'matchAmount': formatMoney(dsg.totalPartido),
              'credit': formatMoney(dsg.saldoFavorAplicado),
            },
          ),
          if (creditoRestante > 0.005)
            NotificationLocale.tr(
              lang,
              'notifMatchPaidWithCreditRemaining',
              params: {'amount': formatMoney(creditoRestante)},
            ),
        ].join('\n');

        final ok = await _entregarCobroJugador(
          uid: uid,
          targetId: targetId,
          partidoId: partidoId,
          titulo: titulo,
          cuerpo: cuerpo,
          detalleTexto: detalleTexto,
          type: 'cobro_partido_favor',
        );
        if (ok) enviados++;
      }),
    );

    return enviados;
  }

  /// Local inmediata si sos el destinatario + push FCM.
  /// Antes, al ser organizador=jugador, solo salía local y se salteaba el push.
  Future<bool> _entregarCobroJugador({
    required String? uid,
    required String targetId,
    required int partidoId,
    required String titulo,
    required String cuerpo,
    required String detalleTexto,
    required String type,
  }) async {
    final esSelf = uid != null && uid == targetId;
    if (esSelf) {
      // Misma sesión: solo notificación del sistema (sin SnackBar negro duplicado
      // ni FCM que vuelva a disparar otra local en foreground).
      await NotificationService.instance.showCobroPartido(
        partidoId: partidoId,
        titulo: titulo,
        cuerpo: cuerpo,
        detalle: detalleTexto,
      );
      return true;
    }

    await PushNotificationService.instance.enviar(
      userIds: [targetId],
      title: titulo,
      body: cuerpo,
      playerNotifyType: type == 'cobro_partido' ? 'cobro_partido' : null,
      playerNotifyPartidoId: type == 'cobro_partido' ? partidoId : null,
      data: {
        'type': type,
        'partido_id': '$partidoId',
        'detalle': _truncar(detalleTexto, 900),
      },
    );
    return true;
  }

  String _detalleSimple(
    Partido partido,
    DetallePartido det,
    double monto,
    String lang,
  ) {
    final sportParams = _sportParams(partido.sportType, lang);
    final lineas = <String>[
      NotificationLocale.tr(
        lang,
        'notifMatchChargeDetailHeader',
        params: {
          'date': formatFecha(partido.fecha),
          ...sportParams,
        },
      ),
      if (partido.recinto?.trim().isNotEmpty ?? false)
        NotificationLocale.tr(
          lang,
          'notifMatchChargeDetailVenue',
          params: {'venue': partido.recinto!.trim()},
        ),
      '',
      NotificationLocale.tr(
        lang,
        'notifMatchChargeDetailAmount',
        params: {'amount': formatMoney(monto)},
      ),
      NotificationLocale.tr(lang, 'notifMatchChargeDetailHint'),
    ];
    return lineas.join('\n');
  }

  String _truncar(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  /// Jugador subió comprobante → avisa al organizador del partido.
  Future<void> notificarComprobanteOrganizador({
    required int detalleId,
    required int partidoId,
    required String organizadorId,
    required String jugadorNombre,
    required double monto,
    required bool esAbono,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      final orgId = organizadorId.trim().isNotEmpty
          ? organizadorId.trim()
          : await _organizadorIdDePartido(partidoId);
      if (orgId == null || orgId.isEmpty) return;

      // Defensa: el partido debe pertenecer a ese organizador.
      final orgPartido = await _organizadorIdDePartido(partidoId);
      if (orgPartido == null || orgPartido.isEmpty || orgPartido != orgId) {
        appLog(
          'CobroNotificacionService.notificarComprobanteOrganizador: '
          'organizador no coincide con partido $partidoId',
        );
        return;
      }

      final lang = await NotificationLocale.forUser(orgId);
      final tipo = esAbono
          ? NotificationLocale.tr(lang, 'notifReceiptTypePartialArticle')
          : NotificationLocale.tr(lang, 'notifReceiptTypeFullArticle');
      final tituloLoc = NotificationLocale.tr(lang, 'notifReceiptPendingTitle');
      final cuerpo = NotificationLocale.tr(
        lang,
        'notifReceiptPendingBody',
        params: {
          'name': jugadorNombre,
          'type': tipo,
          'amount': formatMoney(monto),
        },
      );

      final uid = AuthService.instance.currentUser?.id;
      if (uid != null && uid == orgId) {
        await NotificationService.instance.showComprobantePendiente(
          partidoId: partidoId,
          detalleId: detalleId,
          titulo: tituloLoc,
          cuerpo: cuerpo,
        );
        return;
      }

      await PushNotificationService.instance.enviar(
        userIds: [orgId],
        title: tituloLoc,
        body: cuerpo,
        playerNotifyType: 'comprobante',
        playerNotifyPartidoId: partidoId,
        playerNotifyDetalleId: detalleId,
        data: {
          'type': 'comprobante_pago',
          'partido_id': '$partidoId',
          'detalle_id': '$detalleId',
        },
      );
    } catch (e) {
      appLog('CobroNotificacionService.notificarComprobanteOrganizador: $e');
    }
  }

  /// Organizador rechazó comprobante → avisa al jugador (mensaje genérico).
  Future<void> notificarComprobanteRechazado({
    required int detalleId,
    required int partidoId,
    required String jugadorId,
    required String jugadorNombre,
    required double pendienteNeto,
    required DateTime fechaPartido,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      final targetId = await _resolverIdNotificacion(jugadorId);
      if (targetId.isEmpty) return;

      final lang = await NotificationLocale.forUser(targetId);
      final titulo = NotificationLocale.tr(lang, 'notifReceiptRejectedTitle');
      final cuerpo = NotificationLocale.tr(
        lang,
        'notifReceiptRejectedBody',
        params: {
          'name': formatNombreSaludo(jugadorNombre),
          'date': formatFecha(fechaPartido),
          'amount': formatMoney(pendienteNeto),
        },
      );

      final uid = AuthService.instance.currentUser?.id;
      if (uid != null && uid == targetId) {
        await NotificationService.instance.showComprobanteRechazado(
          partidoId: partidoId,
          titulo: titulo,
          cuerpo: cuerpo,
        );
        return;
      }

      await PushNotificationService.instance.enviar(
        userIds: [targetId],
        title: titulo,
        body: cuerpo,
        playerNotifyType: 'cobro_partido',
        playerNotifyPartidoId: partidoId,
        data: {
          'type': 'comprobante_rechazado',
          'partido_id': '$partidoId',
          'detalle_id': '$detalleId',
        },
      );
    } catch (e) {
      appLog('CobroNotificacionService.notificarComprobanteRechazado: $e');
    }
  }

  String _resumenPush(
    DesgloseJugador d,
    Partido partido,
    String fechaTxt,
    String lang,
  ) {
    final sport = _sportParams(partido.sportType, lang);
    final sportPrefix = '${sport['sportEmoji']} ${sport['sport']} · ';
    final lineas = d.lineas
        .map((l) => '${l.concepto}: ${formatMoney(l.monto)}')
        .join(' · ');
    final recinto = partido.recinto?.trim();
    final lugar = recinto != null && recinto.isNotEmpty ? ' · $recinto' : '';
    final pendiente = d.pendientePartido > 0
        ? NotificationLocale.tr(
            lang,
            'notifMatchChargePending',
            params: {'amount': formatMoney(d.pendientePartido)},
          )
        : NotificationLocale.tr(
            lang,
            'notifMatchChargeOwes',
            params: {
              'amount': formatMoney(
                d.netoAPagarPartido > 0 ? d.netoAPagarPartido : d.totalPartido,
              ),
            },
          );
    if (lineas.isEmpty) {
      return '$sportPrefix$fechaTxt$lugar$pendiente${NotificationLocale.tr(lang, 'notifMatchChargeOpenApp')}';
    }
    return '$sportPrefix$fechaTxt$lugar · $lineas$pendiente';
  }

  Map<String, String> _sportParams(SportType sport, String lang) {
    return {
      'sportEmoji': SportThemeConfig.paletteFor(sport).emoji,
      'sport': sport.labelForLang(lang),
    };
  }

  Future<String> _resolverIdNotificacion(String jugadorId) async {
    final jugador = await _jugadorRepo.getById(jugadorId);
    if (jugador == null) return jugadorId;
    final email = jugador.contactEmail;
    if (email != null && email.isNotEmpty) {
      final porEmail = await _jugadorRepo.getByEmail(email);
      if (porEmail?.supabaseId != null && porEmail!.supabaseId!.isNotEmpty) {
        return porEmail.supabaseId!;
      }
    }
    return jugadorId;
  }

  /// Solo el organizador dueño del partido. Sin fallback a “cualquier organizer”.
  Future<String?> _organizadorIdDePartido(int partidoId) async {
    final row = await SupabaseHelpers.client
        .from('partidos')
        .select('organizador_id')
        .eq('id', partidoId)
        .maybeSingle();
    final orgId = row?['organizador_id']?.toString().trim();
    if (orgId == null || orgId.isEmpty) return null;
    return orgId;
  }
}
