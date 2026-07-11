import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

/// Envía push FCM vía Supabase Edge Function `send-push`.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  SupabaseClient? get _client {
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  Future<void> enviar({
    required List<String> userIds,
    required String title,
    required String body,
    Map<String, String>? data,
    int? playerNotifyPartidoId,
    String? playerNotifyType,
    int? playerNotifyDetalleId,
  }) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;

    final client = _client;
    if (client == null) return;

    try {
      final response = await client.functions.invoke(
        'send-push',
        body: {
          'user_ids': ids,
          'title': title,
          'body': body,
          'data': data ?? {},
          if (playerNotifyPartidoId != null)
            'player_notify_partido_id': playerNotifyPartidoId,
          if (playerNotifyType != null)
            'player_notify_type': playerNotifyType,
          if (playerNotifyDetalleId != null)
            'player_notify_detalle_id': playerNotifyDetalleId,
        },
      );
      if (response.status != 200) {
        debugPrint(
          'PushNotificationService status ${response.status}: ${response.data}',
        );
      } else if (response.data is Map) {
        final sent = (response.data as Map)['sent'];
        if (sent == 0) {
          debugPrint(
            'PushNotificationService: sin tokens FCM para $ids',
          );
        }
      }
    } catch (e) {
      debugPrint('PushNotificationService: $e');
    }
  }
}
