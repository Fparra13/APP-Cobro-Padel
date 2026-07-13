import 'package:flutter/foundation.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
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

/// Push de cobros: jugadores reciben detalle; organizador recibe comprobantes.
class CobroNotificacionService {
  final _jugadorRepo = JugadorRepositoryRemote();
  final _prefs = PreferencesService();

  /// Tras registrar cobros del partido, notifica a cada jugador con deuda.
  Future<void> notificarCobrosPartido(int partidoId) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      final repos = AppRepositories.tryActive;
      if (repos == null) return;

      final completo = await repos.getPartidoCompleto(partidoId);
      if (completo == null) {
        debugPrint('CobroNotificacion: partido $partidoId no encontrado');
        return;
      }

      final desglose = await repos.getDesglose(partidoId, reconciliar: false);
      final desglosePorId = {
        for (final d in desglose)
          if (d.jugadorSupabaseId != null) d.jugadorSupabaseId!: d,
      };

      final pago = await _prefs.datosPago;
      final fechaTxt = formatDiaCompleto(completo.partido.fecha);
      final uid = AuthService.instance.currentUser?.id;

      final pendientes = completo.detalles.where((d) {
        if (!d.asistio || d.jugadorSupabaseId == null) return false;
        final snap = completo.snapshotSaldoCobro(d);
        if (snap == null) return false;
        return d.tieneDeudaNeto(snapshotSaldoAnterior: snap);
      }).toList();

      var enviados = 0;
      await Future.wait(
        pendientes.map((det) async {
          final jugadorId = det.jugadorSupabaseId!;
          final d = desglosePorId[jugadorId];
          final snap = completo.snapshotSaldoCobro(det);
          final monto = d?.pendientePartido ??
              (snap != null
                  ? det
                      .estadoCobro(snapshotSaldoAnterior: snap)
                      .pendienteNeto
                  : 0);
          if (monto <= 0 && det.total <= 0) return;

          final targetId = await _resolverIdNotificacion(jugadorId);
          if (targetId.isEmpty) return;

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

          if (uid != null && uid == targetId) {
            await NotificationService.instance.showCobroPartido(
              partidoId: partidoId,
              titulo: titulo,
              cuerpo: cuerpo,
              detalle: detalleTexto,
            );
            enviados++;
            return;
          }

          await PushNotificationService.instance.enviar(
            userIds: [targetId],
            title: titulo,
            body: cuerpo,
            data: {
              'type': 'cobro_partido',
              'partido_id': '$partidoId',
              'detalle': _truncar(detalleTexto, 900),
            },
          );
          enviados++;
        }),
      );

      final cubiertosConFavor = completo.detalles.where((d) {
        if (!d.asistio || d.jugadorSupabaseId == null) return false;
        final snap = completo.snapshotSaldoCobro(d);
        if (snap == null) return false;
        if (d.tieneDeudaNeto(snapshotSaldoAnterior: snap)) return false;
        final dsg = desglosePorId[d.jugadorSupabaseId!];
        if (dsg == null) return false;
        return dsg.saldoFavorAplicado > 0.005 &&
            dsg.pendientePartido <= 0.005 &&
            dsg.montoPagado <= 0.005;
      }).toList();

      await Future.wait(
        cubiertosConFavor.map((det) async {
          final jugadorId = det.jugadorSupabaseId!;
          final dsg = desglosePorId[jugadorId]!;
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

          if (uid != null && uid == targetId) {
            await NotificationService.instance.showCobroPartido(
              partidoId: partidoId,
              titulo: titulo,
              cuerpo: cuerpo,
              detalle: detalleTexto,
            );
            enviados++;
            return;
          }

          await PushNotificationService.instance.enviar(
            userIds: [targetId],
            title: titulo,
            body: cuerpo,
            data: {
              'type': 'cobro_partido_favor',
              'partido_id': '$partidoId',
              'detalle': _truncar(detalleTexto, 900),
            },
          );
          enviados++;
        }),
      );

      if (enviados == 0) {
        debugPrint('CobroNotificacion: sin notificaciones en $partidoId');
      } else {
        debugPrint('CobroNotificacion: $enviados push(es) para partido $partidoId');
      }
    } catch (e, st) {
      debugPrint('CobroNotificacionService.notificarCobrosPartido: $e\n$st');
    }
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

  /// Jugador subió comprobante → avisa al organizador.
  Future<void> notificarComprobanteOrganizador({
    required int detalleId,
    required int partidoId,
    required String jugadorNombre,
    required double monto,
    required bool esAbono,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      final orgId = await _resolverOrganizadorId(partidoId);
      if (orgId == null || orgId.isEmpty) return;

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
      debugPrint('CobroNotificacionService.notificarComprobanteOrganizador: $e');
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
        NotificationService.instance.showInAppSnack(cuerpo);
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
      debugPrint('CobroNotificacionService.notificarComprobanteRechazado: $e');
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

  Future<String?> _resolverOrganizadorId(int partidoId) async {
    final row = await SupabaseHelpers.client
        .from('partidos')
        .select('organizador_id')
        .eq('id', partidoId)
        .maybeSingle();
    final orgId = row?['organizador_id']?.toString();
    if (orgId != null && orgId.isNotEmpty) return orgId;

    final fallback = await SupabaseHelpers.client
        .from('profiles')
        .select('id')
        .inFilter('role', ['organizer', 'organizador'])
        .eq('activo', true)
        .limit(1)
        .maybeSingle();
    return fallback?['id']?.toString();
  }
}
