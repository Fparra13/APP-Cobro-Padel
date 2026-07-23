import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/auth_service.dart';
import '../core/firebase_config.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import 'notification_locale.dart';
import 'notification_service.dart';
import '../utils/app_log.dart';

/// Resultado de intentar registrar el dispositivo para push.
enum FcmSyncResult {
  synced,
  notLoggedIn,
  firebaseUnavailable,
  tokenUnavailable,
  updateFailed,
}

/// Registro del token FCM y recepción de push remotos.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  FirebaseMessaging? _messaging;
  bool _initialized = false;
  Completer<bool>? _initCompleter;

  bool get isAvailable => _initialized;

  FirebaseMessaging? get _messagingOrNull {
    if (Firebase.apps.isEmpty) return null;
    return _messaging ??= FirebaseMessaging.instance;
  }

  /// No bloquea la UI: puede llamarse sin await tras el login.
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  /// Reinicia el estado de FCM (p. ej. botón Probar tras un fallo).
  void resetForRetry() {
    _initialized = false;
    _messaging = null;
    _initCompleter = null;
  }

  /// Espera si hay un init en curso; permite reintentar si falló.
  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    if (!FirebaseConfig.isConfigured) {
      await _reportRegisterError(
        AuthService.instance.currentUser?.id,
        'firebase_not_configured',
      );
      return false;
    }
    if (!SupabaseConfig.isConfigured) {
      await _reportRegisterError(
        AuthService.instance.currentUser?.id,
        'supabase_not_configured',
      );
      return false;
    }

    final inFlight = _initCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _initCompleter = completer;

    try {
      final ok = await FirebaseConfig.ensureInitialized()
          .timeout(const Duration(seconds: 20));
      if (!ok) {
        await _reportRegisterError(
          AuthService.instance.currentUser?.id,
          FirebaseConfig.lastInitError ?? 'firebase_init_false',
        );
        completer.complete(false);
        return false;
      }

      final messaging = _messagingOrNull;
      if (messaging == null) {
        await _reportRegisterError(
          AuthService.instance.currentUser?.id,
          'messaging_null apps=${Firebase.apps.length}',
        );
        completer.complete(false);
        return false;
      }

      try {
        await messaging
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
            )
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        appLog('FCM requestPermission: $e');
      }

      try {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        appLog('FCM setForegroundNotificationPresentationOptions: $e');
      }

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
      messaging.onTokenRefresh.listen((_) {
        unawaited(syncTokenToProfile());
      });

      _initialized = true;
      completer.complete(true);

      unawaited(syncTokenToProfile());
      unawaited(touchAppLastSeen());

      try {
        final initial = await messaging
            .getInitialMessage()
            .timeout(const Duration(seconds: 5));
        if (initial != null) {
          await _handleRemoteMessage(initial);
        }
      } catch (e) {
        appLog('FCM getInitialMessage: $e');
      }

      return true;
    } catch (e) {
      appLog('FCM init failed: $e');
      await _reportRegisterError(
        AuthService.instance.currentUser?.id,
        'fcm_init_exception:$e',
      );
      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      if (!_initialized) {
        // Permite reintentar en el próximo open / Probar.
        _initCompleter = null;
      }
    }
  }

  /// Marca que el usuario abrió la app (badge "Tiene Kloovi").
  Future<void> touchAppLastSeen() async {
    if (!AuthService.instance.isLoggedIn) return;
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return;
    try {
      await SupabaseHelpers.client
          .from('profiles')
          .update({'app_last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid);
    } catch (e) {
      appLog('FCM touchAppLastSeen: $e');
    }
  }

  Future<void> _reportRegisterError(String? uid, String error) async {
    if (uid == null) return;
    try {
      final trimmed = error.length > 480 ? error.substring(0, 480) : error;
      await SupabaseHelpers.client.from('profiles').update({
        'fcm_register_error': trimmed,
        'app_last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      appLog('FCM reportRegisterError: $e');
    }
  }

  /// True si el perfil remoto ya tiene token (push puede estar activo).
  Future<bool> profileHasFcmToken() async {
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null || !SupabaseConfig.isConfigured) return false;
    try {
      final row = await SupabaseHelpers.client
          .from('profiles')
          .select('fcm_token')
          .eq('id', uid)
          .maybeSingle();
      final token = (row?['fcm_token'] as String?)?.trim() ?? '';
      return token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// QA: sonda initializeApp + getToken y persiste el resultado en
  /// `profiles.fcm_register_error`. No cambia el flujo de sync.
  ///
  /// Necesario en release: [appLog] solo imprime en debug.
  Future<String> runQaDiagnostics() async {
    final uid = AuthService.instance.currentUser?.id;
    final buf = StringBuffer('qa1');

    buf.write('|cfg=${FirebaseConfig.isConfigured}');
    buf.write('|apps0=${Firebase.apps.length}');
    buf.write('|fcmInitFlag=$_initialized');

    // 1) initializeApp
    try {
      final ok = await FirebaseConfig.ensureInitialized()
          .timeout(const Duration(seconds: 20));
      buf.write('|initOk=$ok');
      if (FirebaseConfig.lastInitError != null) {
        buf.write('|initErr=${FirebaseConfig.lastInitError}');
      }
    } catch (e, st) {
      buf.write('|initEx=${e.runtimeType}:$e');
      buf.write('|initSt=${st.toString().split('\n').take(3).join('>')}');
    }

    buf.write('|apps1=${Firebase.apps.length}');

    // 2) getToken (una sola vez; no reintentos)
    if (Firebase.apps.isEmpty) {
      buf.write('|token=skipped_no_apps');
    } else {
      try {
        final messaging = FirebaseMessaging.instance;
        final token = await messaging
            .getToken()
            .timeout(const Duration(seconds: 20));
        final len = token?.trim().length ?? 0;
        buf.write('|tokenLen=$len');
        buf.write('|tokenNull=${token == null}');
      } catch (e, st) {
        buf.write('|tokenEx=${e.runtimeType}:$e');
        buf.write('|tokenSt=${st.toString().split('\n').take(3).join('>')}');
      }
    }

    final report = buf.toString();
    appLog('FCM QA diagnostics: $report');
    await _reportRegisterError(uid, report);
    return report;
  }

  /// Reintenta getToken: en Android suele fallar la 1ª vez (Play Services).
  Future<String?> _fetchTokenWithRetry(FirebaseMessaging messaging) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        if (attempt > 1) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
        try {
          await messaging.setAutoInitEnabled(true);
        } catch (_) {}

        final token = await messaging
            .getToken()
            .timeout(const Duration(seconds: 20));
        if (token != null && token.trim().isNotEmpty) {
          return token.trim();
        }
        lastError = 'empty_token';
        appLog('FCM getToken attempt $attempt: empty');
      } catch (e) {
        lastError = e;
        appLog('FCM getToken attempt $attempt: $e');
      }
    }
    throw StateError('getToken failed after retries: $lastError');
  }

  Future<FcmSyncResult> syncTokenToProfile({bool forceReinit = false}) async {
    if (!AuthService.instance.isLoggedIn) return FcmSyncResult.notLoggedIn;

    final uid = AuthService.instance.currentUser?.id;

    if (forceReinit) {
      resetForRetry();
    }

    // Permiso Android 13+ antes de pedir token (local + FCM).
    try {
      await NotificationService.instance.requestPermissions();
      await NotificationService.instance.ensureAndroidChannels();
    } catch (e) {
      appLog('FCM pre-permission: $e');
    }

    final ready = await _ensureInitialized();
    if (!ready) {
      // _ensureInitialized ya reportó el error concreto.
      return FcmSyncResult.firebaseUnavailable;
    }

    final messaging = _messagingOrNull;
    if (messaging == null) {
      await _reportRegisterError(uid, 'messaging_null');
      return FcmSyncResult.firebaseUnavailable;
    }

    try {
      try {
        await messaging
            .requestPermission(alert: true, badge: true, sound: true)
            .timeout(const Duration(seconds: 10));
      } catch (_) {}

      final token = await _fetchTokenWithRetry(messaging);
      if (token == null || uid == null) {
        await _reportRegisterError(uid, 'token_unavailable');
        return FcmSyncResult.tokenUnavailable;
      }

      await SupabaseHelpers.client.from('profiles').update({
        'fcm_token': token,
        'fcm_register_error': null,
        'app_last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);

      appLog('FCM syncToken: OK len=${token.length}');
      return FcmSyncResult.synced;
    } catch (e) {
      appLog('FCM syncToken: $e');
      await _reportRegisterError(uid, e.toString());
      return FcmSyncResult.updateFailed;
    }
  }

  Future<void> clearTokenOnLogout() async {
    final messaging = _messagingOrNull;
    try {
      final uid = AuthService.instance.currentUser?.id;
      if (uid != null && SupabaseConfig.isConfigured) {
        await SupabaseHelpers.client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', uid);
      }
      if (messaging != null) {
        await messaging.deleteToken();
      }
    } catch (_) {}
    _initialized = false;
    _messaging = null;
    _initCompleter = null;
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

    if (type == 'cobro_partido' || type == 'cobro_recordatorio_auto') {
      await NotificationService.instance.showCobroPartido(
        partidoId: partidoId,
        titulo: title,
        cuerpo: body,
        detalle: data['detalle'] ?? data['detalle_id'],
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

    if (type == 'convocatoria_cancelada') {
      await NotificationService.instance.showConvocatoriaMensaje(
        partidoId: partidoId,
        titulo: title,
        cuerpo: body,
        idOffset: 4200,
        esCancelacion: true,
      );
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
    } else if (type == 'cobro_partido' || type == 'cobro_recordatorio_auto') {
      appLog('FCM_NAV_RECEIVED type=$type');
      await NotificationService.instance.openMisCobros();
    } else if (type == 'comprobante_pago') {
      await NotificationService.instance.openOrganizerHomePagos();
    } else if (type == 'convocatoria_cancelada') {
      await NotificationService.instance.openCancelacion(partidoId);
    } else if (type == 'convocatoria' ||
        type == 'convocatoria_reprogramada' ||
        type == 'convocatoria_recordatorio') {
      await NotificationService.instance.openConvocatoria(partidoId);
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseConfig.ensureInitialized();
}
