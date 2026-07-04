import 'package:flutter/foundation.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../core/supabase_helpers.dart';
import '../core/supabase_config.dart';
import '../models/jugador.dart';
import '../services/notification_locale.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../utils/formatters.dart';

/// Notificaciones de convocatoria: push FCM (otros teléfonos) + local (mismo dispositivo).
class ConvocatoriaNotificacionService {
  Future<void> notificarConvocatoriaTitulares({
    required List<Jugador> titulares,
    required int partidoId,
    required DateTime fecha,
    required int horasLimite,
    required String recinto,
    required SportType sportType,
  }) async {
    final uid = AuthService.instance.currentUser?.id;
    final venue = recinto.trim();
    final fechaHora = formatFechaHora(fecha);
    final emoji = SportThemeConfig.paletteFor(sportType).emoji;

    for (final jugador in titulares) {
      final id = await _resolverIdNotificacion(jugador);
      if (id.isEmpty) continue;

      final lang = await NotificationLocale.forUser(id);
      final sportLabel = sportType.labelForLang(lang);
      final params = {
        'emoji': emoji,
        'sport': sportLabel,
        'venue': venue,
        'date': fechaHora,
        'hours': '$horasLimite',
      };
      final titulo = NotificationLocale.tr(
        lang,
        'notifConvocadoTitle',
        params: params,
      );
      final cuerpo = NotificationLocale.tr(
        lang,
        'notifConvocadoBodyInApp',
        params: params,
      );

      if (uid != null && id == uid) {
        await NotificationService.instance.showConvocatoriaInvitacion(
          partidoId: partidoId,
          fecha: fecha,
          horasLimite: horasLimite,
          titulo: titulo,
          cuerpo: cuerpo,
        );
        continue;
      }

      if (!SupabaseConfig.isConfigured) continue;

      try {
        await PushNotificationService.instance.enviar(
          userIds: [id],
          title: titulo,
          body: cuerpo,
          data: {
            'type': 'convocatoria',
            'partido_id': '$partidoId',
            'horas_limite': '$horasLimite',
            'sport_type': sportType.dbValue,
            'recinto': venue,
          },
        );
      } catch (e) {
        debugPrint('Push convocatoria (no bloquea envío): $e');
      }
    }
  }

  /// Recordatorio cuando queda menos de 1 h de plazo.
  Future<void> notificarRecordatorioPlazo({
    required Jugador jugador,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
  }) async {
    await _enviarAJugadorConvocatoria(
      jugador: jugador,
      partidoId: partidoId,
      tituloKey: 'notifDeadlineReminderTitle',
      cuerpoKey: 'notifDeadlineReminderBody',
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      localIdOffset: 2000,
    );
  }

  /// Aviso suave al vencer el plazo sin respuesta.
  Future<void> notificarPlazoVencido({
    required Jugador jugador,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
  }) async {
    await _enviarAJugadorConvocatoria(
      jugador: jugador,
      partidoId: partidoId,
      tituloKey: 'notifDeadlineMissedTitle',
      cuerpoKey: 'notifDeadlineMissedBody',
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      localIdOffset: 3000,
    );
  }

  Future<void> _enviarAJugadorConvocatoria({
    required Jugador jugador,
    required int partidoId,
    required String tituloKey,
    required String cuerpoKey,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
    required int localIdOffset,
  }) async {
    final uid = AuthService.instance.currentUser?.id;
    final id = await _resolverIdNotificacion(jugador);
    if (id.isEmpty) return;

    final lang = await NotificationLocale.forUser(id);
    final params = {
      'emoji': SportThemeConfig.paletteFor(sportType).emoji,
      'sport': sportType.labelForLang(lang),
      'venue': recinto.trim().isEmpty ? '—' : recinto.trim(),
      'date': formatFechaHora(fecha),
    };
    final titulo = NotificationLocale.tr(lang, tituloKey, params: params);
    final cuerpo = NotificationLocale.tr(lang, cuerpoKey, params: params);

    if (uid != null && id == uid) {
      await NotificationService.instance.showConvocatoriaMensaje(
        partidoId: partidoId,
        titulo: titulo,
        cuerpo: cuerpo,
        idOffset: localIdOffset,
      );
      return;
    }

    if (!SupabaseConfig.isConfigured) return;
    try {
      await PushNotificationService.instance.enviar(
        userIds: [id],
        title: titulo,
        body: cuerpo,
        data: {
          'type': 'convocatoria',
          'partido_id': '$partidoId',
        },
      );
    } catch (e) {
      debugPrint('Push convocatoria plazo: $e');
    }
  }

  Future<void> notificarPromocionTitular({
    required Jugador jugador,
    required int partidoId,
  }) async {
    final uid = AuthService.instance.currentUser?.id;
    final id = await _resolverIdNotificacion(jugador);
    if (id.isEmpty) return;

    final lang = await NotificationLocale.forUser(id);
    final tituloLoc = NotificationLocale.tr(lang, 'notifPromocionTitle');
    final cuerpoLoc = NotificationLocale.tr(lang, 'notifPromocionBodyInApp');

    if (uid != null && id == uid) {
      await NotificationService.instance.showPromocionTitular(
        partidoId: partidoId,
      );
    }

    if (!SupabaseConfig.isConfigured) return;

    try {
      await PushNotificationService.instance.enviar(
        userIds: [id],
        title: tituloLoc,
        body: cuerpoLoc,
        data: {
          'type': 'convocatoria',
          'partido_id': '$partidoId',
        },
      );
    } catch (e) {
      debugPrint('Push promoción (no bloquea): $e');
    }
  }

  /// Avisa al organizador cuando un jugador confirma o rechaza la convocatoria.
  Future<void> notificarRespuestaOrganizador({
    required int partidoId,
    required bool confirmo,
    required String jugadorNombre,
    DateTime? fechaPartido,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      var fecha = fechaPartido ?? DateTime.now();
      String? orgIdFromPartido;

      try {
        final row = await SupabaseHelpers.client
            .from('partidos')
            .select('organizador_id, fecha')
            .eq('id', partidoId)
            .maybeSingle();
        if (row != null) {
          orgIdFromPartido = row['organizador_id']?.toString();
          final f = row['fecha'] as String?;
          if (f != null) fecha = DateTime.parse(f);
        }
      } catch (_) {}

      final orgId = await _resolverOrganizadorId(partidoId, orgIdFromPartido);
      if (orgId == null || orgId.isEmpty) return;

      final lang = await NotificationLocale.forUser(orgId);
      final titulo = NotificationLocale.tr(
        lang,
        confirmo ? 'notifOrganizerConfirmTitle' : 'notifOrganizerDeclineTitle',
      );
      final cuerpo = NotificationLocale.tr(
        lang,
        confirmo ? 'notifOrganizerConfirmBody' : 'notifOrganizerDeclineBody',
        params: {
          'name': jugadorNombre,
          'date': formatDiaCompleto(fecha),
        },
      );

      final uid = AuthService.instance.currentUser?.id;
      if (uid != null && orgId == uid) {
        await NotificationService.instance.showRespuestaConvocatoriaOrganizador(
          partidoId: partidoId,
          titulo: titulo,
          cuerpo: cuerpo,
        );
        return;
      }

      await PushNotificationService.instance.enviar(
        userIds: [orgId],
        title: titulo,
        body: cuerpo,
        playerNotifyType: 'convocatoria_respuesta',
        playerNotifyPartidoId: partidoId,
        data: {
          'type': 'confirmacion_respuesta',
          'partido_id': '$partidoId',
        },
      );
    } catch (e) {
      debugPrint('Push respuesta organizador: $e');
    }
  }

  Future<String> _resolverIdNotificacion(Jugador jugador) async {
    final key = jugador.keyId;
    final email = jugador.contactEmail;
    if (email != null && email.isNotEmpty) {
      try {
        final porEmail = await AppRepositories.I.getJugadorPorEmail(email);
        if (porEmail?.keyId.isNotEmpty == true) return porEmail!.keyId;
      } catch (_) {}
    }
    return key;
  }

  Future<String?> _resolverOrganizadorId(
    int partidoId,
    String? organizadorId,
  ) async {
    if (organizadorId != null && organizadorId.isNotEmpty) {
      return organizadorId;
    }
    try {
      final fallback = await SupabaseHelpers.client
          .from('profiles')
          .select('id')
          .inFilter('role', ['organizer', 'organizador'])
          .eq('activo', true)
          .limit(1)
          .maybeSingle();
      return fallback?['id']?.toString();
    } catch (_) {
      return AuthService.instance.currentUser?.id;
    }
  }
}
