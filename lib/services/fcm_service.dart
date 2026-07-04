import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/auth_service.dart';
import '../core/firebase_config.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import 'notification_locale.dart';
import 'notification_service.dart';

/// Registro del token FCM y recepción de push remotos.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  FirebaseMessaging? _messaging;
  bool _initialized = false;
  bool _initializing = false;

  bool get isAvailable => _initialized;

  FirebaseMessaging? get _messagingOrNull {
    if (Firebase.apps.isEmpty) return null;
    return _messaging ??= FirebaseMessaging.instance;
  }

  /// No bloquea la UI: puede llamarse sin await tras el login.
  Future<void> initialize() async {
    if (_initialized || _initializing || !FirebaseConfig.isConfigured) return;
    if (!SupabaseConfig.isConfigured) return;

    _initializing = true;
    try {
      final ok = await FirebaseConfig.ensureInitialized()
          .timeout(const Duration(seconds: 15));
      if (!ok) return;

      final messaging = _messagingOrNull;
      if (messaging == null) return;

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      try {
        await messaging
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
            )
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('FCM requestPermission: $e');
      }

      try {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        debugPrint('FCM setForegroundNotificationPresentationOptions: $e');
      }

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
      messaging.onTokenRefresh.listen((_) => syncTokenToProfile());

      _initialized = true;

      unawaited(syncTokenToProfile());

      try {
        final initial = await messaging
            .getInitialMessage()
            .timeout(const Duration(seconds: 5));
        if (initial != null) {
          await _handleRemoteMessage(initial);
        }
      } catch (e) {
        debugPrint('FCM getInitialMessage: $e');
      }
    } catch (e) {
      debugPrint('FCM init failed: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> syncTokenToProfile() async {
    if (!_initialized || !AuthService.instance.isLoggedIn) return;

    final messaging = _messagingOrNull;
    if (messaging == null) return;

    try {
      final token = await messaging
          .getToken()
          .timeout(const Duration(seconds: 20));
      final uid = AuthService.instance.currentUser?.id;
      if (token == null || uid == null) return;

      await SupabaseHelpers.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', uid);
    } catch (e) {
      debugPrint('FCM syncToken: $e');
    }
  }

  Future<void> clearTokenOnLogout() async {
    if (!_initialized) return;
    final messaging = _messagingOrNull;
    if (messaging == null) return;
    try {
      final uid = AuthService.instance.currentUser?.id;
      if (uid != null) {
        await SupabaseHelpers.client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', uid);
      }
      await messaging.deleteToken();
    } catch (_) {}
    _initialized = false;
    _messaging = null;
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];
    final partidoId = int.tryParse(data['partido_id'] ?? '');
    final title = message.notification?.title ??
        await NotificationLocale.trCurrent('appName');
    final body = message.notification?.body ??
        message.data['body'] ??
        await NotificationLocale.trCurrent('notifGenericNew');

    if (partidoId == null) return;

    if (type == 'confirmacion_respuesta') {
      await NotificationService.instance.showRespuestaConvocatoriaOrganizador(
        partidoId: partidoId,
        titulo: title,
        cuerpo: body,
      );
      return;
    }

    if (type == 'cobro_partido') {
      await NotificationService.instance.showCobroPartido(
        partidoId: partidoId,
        titulo: title,
        cuerpo: body,
        detalle: data['detalle'],
      );
      return;
    }

    if (type == 'comprobante_pago') {
      final detalleId = int.tryParse(data['detalle_id'] ?? '');
      if (detalleId != null) {
        await NotificationService.instance.showComprobantePendiente(
          partidoId: partidoId,
          detalleId: detalleId,
          titulo: title,
          cuerpo: body,
        );
      }
      return;
    }

    await NotificationService.instance.showConvocatoriaInvitacion(
      partidoId: partidoId,
      fecha: DateTime.now(),
      horasLimite: int.tryParse(data['horas_limite'] ?? '') ?? 24,
      titulo: title,
      cuerpo: body,
    );
  }

  Future<void> _onMessageOpened(RemoteMessage message) async {
    await _handleRemoteMessage(message);
  }

  Future<void> _handleRemoteMessage(RemoteMessage message) async {
    final type = message.data['type'];
    final partidoId = int.tryParse(message.data['partido_id'] ?? '');
    if (partidoId == null) return;

    if (type == 'confirmacion_respuesta') {
      await NotificationService.instance.openPartidoOrganizador(partidoId);
    } else if (type == 'cobro_partido') {
      await NotificationService.instance.openMisCobros();
    } else if (type == 'comprobante_pago') {
      await NotificationService.instance.openOrganizerHomePagos();
    } else if (type == 'convocatoria') {
      await NotificationService.instance.openConvocatoria(partidoId);
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseConfig.ensureInitialized();
}
