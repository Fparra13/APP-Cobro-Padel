import '../core/auth_service.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import '../models/codigo_grupo.dart';
import '../utils/app_log.dart';
import 'notification_locale.dart';
import 'notification_service.dart';
import 'push_notification_service.dart';

/// Avisos al organizador por cambios de membresía del grupo.
class GrupoNotificacionService {
  /// Tras unirse con código: avisa al organizador (unión nueva o rejoin).
  Future<void> notificarOrganizadorNuevoMiembro(UnirseGrupoResult result) async {
    if (!SupabaseConfig.isConfigured) return;
    if (result.yaEstaba) return;
    if (result.organizadorId.isEmpty) return;

    try {
      final uid = AuthService.instance.currentUser?.id;
      var nombre = '';
      if (uid != null) {
        try {
          final row = await SupabaseHelpers.client
              .from('profiles')
              .select('nombre')
              .eq('id', uid)
              .maybeSingle();
          nombre = (row?['nombre'] as String?)?.trim() ?? '';
        } catch (_) {}
      }
      if (nombre.isEmpty) nombre = 'Participante';

      final lang = await NotificationLocale.forUser(result.organizadorId);
      final titulo = NotificationLocale.tr(lang, 'notifOrganizerJoinTitle');
      final cuerpo = NotificationLocale.tr(
        lang,
        'notifOrganizerJoinBody',
        params: {'name': nombre},
      );

      if (uid != null && result.organizadorId == uid) {
        await NotificationService.instance.showGrupoOrganizador(
          titulo: titulo,
          cuerpo: cuerpo,
        );
        return;
      }

      await PushNotificationService.instance.enviar(
        userIds: [result.organizadorId],
        title: titulo,
        body: cuerpo,
        playerNotifyType: 'grupo_join',
        data: {
          'type': 'grupo_join',
          'jugador_id': uid ?? '',
        },
      );
    } catch (e) {
      appLog('GrupoNotificacionService.join: $e');
    }
  }
}
