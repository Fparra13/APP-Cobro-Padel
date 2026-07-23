import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../utils/app_log.dart';

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
    await _invoke(
      userIds: userIds,
      title: title,
      body: body,
      data: data,
      playerNotifyPartidoId: playerNotifyPartidoId,
      playerNotifyType: playerNotifyType,
      playerNotifyDetalleId: playerNotifyDetalleId,
    );
  }

  /// Push remoto al propio usuario (botón Probar). Distinto de la notificación local.
  Future<PushSendResult> enviarPruebaAMiMismo({
    required String userId,
    required String title,
    required String body,
  }) {
    return _invoke(
      userIds: [userId],
      title: title,
      body: body,
      data: const {'type': 'qa_self_test'},
    );
  }

  Future<PushSendResult> _invoke({
    required List<String> userIds,
    required String title,
    required String body,
    Map<String, String>? data,
    int? playerNotifyPartidoId,
    String? playerNotifyType,
    int? playerNotifyDetalleId,
  }) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return const PushSendResult(sent: 0, failed: 0, message: 'sin_destinatarios');
    }

    final client = _client;
    if (client == null) {
      return const PushSendResult(sent: 0, failed: 0, message: 'supabase_no_config');
    }

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
        appLog('PushNotificationService status ${response.status}');
        return PushSendResult(
          sent: 0,
          failed: ids.length,
          message: 'http_${response.status}',
        );
      }
      final raw = response.data;
      if (raw is Map) {
        final sent = (raw['sent'] as num?)?.toInt() ?? 0;
        final failed = (raw['failed'] as num?)?.toInt() ?? 0;
        if (sent == 0) {
          appLog('PushNotificationService: sin tokens FCM para destinatarios');
        }
        return PushSendResult(
          sent: sent,
          failed: failed,
          message: raw['message']?.toString(),
        );
      }
      return const PushSendResult(sent: 0, failed: 0, message: 'respuesta_invalida');
    } catch (e) {
      appLog('PushNotificationService failed');
      return PushSendResult(sent: 0, failed: ids.length, message: 'exception');
    }
  }
}

class PushSendResult {
  final int sent;
  final int failed;
  final String? message;

  const PushSendResult({
    required this.sent,
    required this.failed,
    this.message,
  });

  bool get ok => sent > 0 && failed == 0;
}
