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
    await _notificarJugadoresBatch(
      jugadores: titulares,
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      tituloKey: 'notifConvocadoTitle',
      cuerpoKey: 'notifConvocadoBodyInApp',
      pushType: 'convocatoria',
      horasLimite: horasLimite,
      localIdOffset: 1000,
      onSelf: (titulo, cuerpo) async {
        await NotificationService.instance.showConvocatoriaInvitacion(
          partidoId: partidoId,
          fecha: fecha,
          horasLimite: horasLimite,
          titulo: titulo,
          cuerpo: cuerpo,
        );
      },
    );
  }

  /// Aviso a titular cuando el partido se reprograma (debe volver a confirmar).
  Future<void> notificarReprogramacionTitular({
    required Jugador jugador,
    required int partidoId,
    required DateTime fecha,
    required int horasLimite,
    required String recinto,
    required SportType sportType,
  }) async {
    await notificarReprogramacionTitulares(
      jugadores: [jugador],
      partidoId: partidoId,
      fecha: fecha,
      horasLimite: horasLimite,
      recinto: recinto,
      sportType: sportType,
    );
  }

  Future<int> notificarReprogramacionTitulares({
    required List<Jugador> jugadores,
    required int partidoId,
    required DateTime fecha,
    required int horasLimite,
    required String recinto,
    required SportType sportType,
  }) {
    return _notificarJugadoresBatch(
      jugadores: jugadores,
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      tituloKey: 'notifReprogramadoTitle',
      cuerpoKey: 'notifReprogramadoBody',
      pushType: 'convocatoria_reprogramada',
      horasLimite: horasLimite,
      localIdOffset: 4000,
    );
  }

  /// Aviso cuando el organizador cancela el partido (un destinatario).
  Future<void> notificarCancelacionTitular({
    required Jugador jugador,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
  }) async {
    await notificarCancelacionTitulares(
      jugadores: [jugador],
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
    );
  }

  /// Cancela: 1 query de locales + 1 push por idioma (no N× edge function).
  Future<int> notificarCancelacionTitulares({
    required List<Jugador> jugadores,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
  }) {
    return _notificarJugadoresBatch(
      jugadores: jugadores,
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      tituloKey: 'notifCanceladoTitle',
      cuerpoKey: 'notifCanceladoBody',
      pushType: 'convocatoria_cancelada',
      localIdOffset: 4200,
      esCancelacion: true,
    );
  }

  /// Recordatorio manual del organizador a invitados sin respuesta.
  Future<void> notificarRecordatorioManual({
    required Jugador jugador,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
  }) async {
    await notificarRecordatorioManualTitulares(
      jugadores: [jugador],
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
    );
  }

  Future<int> notificarRecordatorioManualTitulares({
    required List<Jugador> jugadores,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
  }) {
    return _notificarJugadoresBatch(
      jugadores: jugadores,
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      sportType: sportType,
      tituloKey: 'notifRecordatorioManualTitle',
      cuerpoKey: 'notifRecordatorioManualBody',
      pushType: 'convocatoria_recordatorio',
      localIdOffset: 4100,
    );
  }

  /// Batch genérico: resolve ids + locales + 1 push por idioma.
  Future<int> _notificarJugadoresBatch({
    required List<Jugador> jugadores,
    required int partidoId,
    required DateTime fecha,
    required String recinto,
    required SportType sportType,
    required String tituloKey,
    required String cuerpoKey,
    required String pushType,
    int? horasLimite,
    int localIdOffset = 0,
    bool esCancelacion = false,
    Future<void> Function(String titulo, String cuerpo)? onSelf,
  }) async {
    if (jugadores.isEmpty) return 0;

    final uid = AuthService.instance.currentUser?.id;
    final resolved = await Future.wait(
      jugadores.map(_resolverIdNotificacion),
    );
    final ids = resolved.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return 0;

    final locales = await _preferredLocalesBatch(ids);
    final fallbackLang = await NotificationLocale.currentLanguageCode();
    final byLang = <String, List<String>>{};
    for (final id in ids) {
      final lang = locales[id] ?? fallbackLang;
      byLang.putIfAbsent(lang, () => []).add(id);
    }

    final venue = recinto.trim().isEmpty ? '—' : recinto.trim();
    final fechaHora = formatFechaHora(fecha);
    final emoji = SportThemeConfig.paletteFor(sportType).emoji;
    var enviados = 0;

    for (final entry in byLang.entries) {
      final lang = entry.key;
      final userIds = entry.value;
      final params = {
        'emoji': emoji,
        'sport': sportType.labelForLang(lang),
        'venue': venue,
        'date': fechaHora,
        if (horasLimite != null) 'hours': '$horasLimite',
      };
      final titulo = NotificationLocale.tr(lang, tituloKey, params: params);
      final cuerpo = NotificationLocale.tr(lang, cuerpoKey, params: params);

      final self = uid != null && userIds.contains(uid);
      final remoteIds = userIds.where((id) => id != uid).toList();

      if (self) {
        if (onSelf != null) {
          await onSelf(titulo, cuerpo);
        } else {
          await NotificationService.instance.showConvocatoriaMensaje(
            partidoId: partidoId,
            titulo: titulo,
            cuerpo: cuerpo,
            idOffset: localIdOffset,
            esCancelacion: esCancelacion,
          );
        }
        enviados++;
      }

      if (remoteIds.isNotEmpty && SupabaseConfig.isConfigured) {
        try {
          await PushNotificationService.instance.enviar(
            userIds: remoteIds,
            title: titulo,
            body: cuerpo,
            data: {
              'type': pushType,
              'partido_id': '$partidoId',
              if (horasLimite != null) 'horas_limite': '$horasLimite',
              'sport_type': sportType.dbValue,
              'recinto': venue,
            },
          );
          enviados += remoteIds.length;
        } catch (e) {
          debugPrint('Push batch ($pushType): $e');
        }
      }
    }
    return enviados;
  }

  Future<Map<String, String>> _preferredLocalesBatch(List<String> userIds) async {
    if (userIds.isEmpty || !SupabaseConfig.isConfigured) return {};
    try {
      final rows = await SupabaseHelpers.client
          .from('profiles')
          .select('id, preferred_locale')
          .inFilter('id', userIds);
      final map = <String, String>{};
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        final rawLocale = row['preferred_locale']?.toString().trim();
        if (id == null || id.isEmpty) continue;
        if (rawLocale != null && rawLocale.isNotEmpty) {
          map[id] = rawLocale.split('_').first;
        }
      }
      return map;
    } catch (_) {
      return {};
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
    int? horasLimite,
    String pushType = 'convocatoria',
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
        esCancelacion: pushType == 'convocatoria_cancelada',
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
          'type': pushType,
          'partido_id': '$partidoId',
          if (horasLimite != null) 'horas_limite': '$horasLimite',
          'sport_type': sportType.dbValue,
          'recinto': recinto.trim(),
        },
      );
    } catch (e) {
      debugPrint('Push convocatoria plazo: $e');
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
