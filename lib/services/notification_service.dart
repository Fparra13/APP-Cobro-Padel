import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../l10n/matchpay_strings.dart';
import '../l10n/translation_maps.dart';
import '../models/mi_convocatoria.dart';
import '../screens/mis_cobros_screen.dart';
import '../screens/organizar_partido_screen.dart';
import '../screens/responder_convocatoria_screen.dart';
import '../utils/app_log.dart';
import '../utils/formatters.dart';
import '../utils/partido_cancelado_popup_flow.dart';
import '../widgets/mis_invitaciones_panel.dart';
import '../widgets/recordatorio_deudores_sheet.dart';
import 'preferences_service.dart';

/// Intención de navegación diferida hasta que el shell esté listo.
enum PendingNavigation {
  misCobros,
}

/// Notificaciones locales para avisar de jugadores impagos.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  // v2: IDs nuevos. Android no actualiza importancia de un canal ya creado
  // (p. ej. auto-creado por FCM en silenciado). Un ID nuevo deja el canal ON
  // por defecto al aceptar notificaciones.
  static const channelId = 'kloovi_recordatorios_v2';
  static const channelConvocatoriaId = 'kloovi_convocatorias_v2';
  static const _legacyChannelIds = [
    'recordatorio_deudores',
    'convocatorias',
  ];
  static const payloadRecordatorio = 'recordatorio_deudores';
  static const payloadConvocatoriaPrefix = 'convocatoria:';
  static const payloadCancelacionPrefix = 'cancelacion:';
  static const payloadOrganizadorPartidoPrefix = 'organizador_partido:';
  static const payloadCobroPrefix = 'cobro:';
  static const payloadComprobantePrefix = 'comprobante:';
  static const idDeudores = 1001;
  static const idDiaria = 1002;
  static const idConvocatoriaBase = 2000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _prefs = PreferencesService();

  AppRepositories? get _repos => AppRepositories.tryActive;

  void _snackReposUnavailable(BuildContext ctx) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(ctx.l10n.tr('reposUnavailableSnackbar'))),
    );
  }

  GlobalKey<NavigatorState>? navigatorKey;
  GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
  bool _initialized = false;
  bool _launchPayloadHandledThisSession = false;
  VoidCallback? onNavigateOrganizerHome;
  VoidCallback? onNavigateOrganizerMisCobros;
  VoidCallback? onNavigatePlayerMisCobros;
  PendingNavigation? _pendingNavigation;

  static const _prefsLaunchPayload = 'notif_launch_payload_handled';
  static const _prefsLaunchAt = 'notif_launch_payload_at';

  void registerOrganizerHomeNavigation(VoidCallback callback) {
    onNavigateOrganizerHome = callback;
  }

  void registerOrganizerMisCobrosNavigation(VoidCallback callback) {
    onNavigateOrganizerMisCobros = callback;
  }

  void registerPlayerMisCobrosNavigation(VoidCallback callback) {
    onNavigatePlayerMisCobros = callback;
  }

  /// Ejecuta navegación FCM/local pendiente cuando el shell ya montó.
  void flushPendingNavigation() {
    if (_pendingNavigation != PendingNavigation.misCobros) return;
    if (_tryOpenMisCobros()) {
      _pendingNavigation = null;
    }
  }

  Future<String> _languageCode() => AppSettingsController.readLanguageCode();

  Future<String> _tr(
    String key, {
    Map<String, String> params = const {},
  }) async {
    return TranslationMaps.lookup(
      await _languageCode(),
      key,
      params: params,
    );
  }

  Future<void> initialize({
    required GlobalKey<NavigatorState> navKey,
    GlobalKey<ScaffoldMessengerState>? messengerKey,
  }) async {
    if (_initialized) return;
    navigatorKey = navKey;
    scaffoldMessengerKey = messengerKey;

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.local);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await ensureAndroidChannels();

    _initialized = true;
  }

  /// Crea canales con importancia alta/máxima (activos por defecto).
  /// Seguro llamar tras conceder permisos o antes de sync FCM.
  Future<void> ensureAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final legacyId in _legacyChannelIds) {
      try {
        await android.deleteNotificationChannel(legacyId);
      } catch (_) {}
    }

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        await _tr('notifChannelRemindersName'),
        description: await _tr('notifChannelRemindersDesc'),
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        channelConvocatoriaId,
        await _tr('notifChannelConvocatoriaName'),
        description: await _tr('notifChannelConvocatoriaDesc'),
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == payloadRecordatorio) {
      _abrirRecordatorioDeudores();
    } else if (payload != null && payload.startsWith(payloadCobroPrefix)) {
      appLog('FCM_NAV_RECEIVED type=local_cobro');
      _abrirMisCobros();
    } else if (payload != null &&
        payload.startsWith(payloadComprobantePrefix)) {
      _abrirOrganizerHomePagos();
    } else if (payload != null &&
        payload.startsWith(payloadOrganizadorPartidoPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadOrganizadorPartidoPrefix.length),
      );
      if (id != null) _abrirPartidoOrganizador(id);
    } else if (payload != null &&
        payload.startsWith(payloadCancelacionPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadCancelacionPrefix.length),
      );
      if (id != null) {
        _abrirCancelacion(id);
      }
    } else if (payload != null &&
        payload.startsWith(payloadConvocatoriaPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadConvocatoriaPrefix.length),
      );
      if (id != null) {
        _abrirConvocatoria(id, soloSiPendiente: true);
      }

  }

  Future<bool> requestPermissions() async {
    var granted = true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // Solo notificaciones. No pedir alarmas exactas: los recordatorios de
      // cobro son server-driven (Supabase + FCM) y no usan AlarmManager.
      granted = await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      granted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    if (granted) {
      await ensureAndroidChannels();
    }

    return granted;
  }

  Future<bool> arePermissionsGranted() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final perms = await ios.checkPermissions();
      return perms?.isEnabled ?? false;
    }
    return true;
  }

  Future<NotificationDetails> _details() async {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        await _tr('notifChannelRemindersName'),
        channelDescription: await _tr('notifChannelRemindersDesc'),
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  /// Cancela el alarm diario local (recordatorios de cobro pasan al servidor).
  Future<void> syncSchedule() async {
    if (!_initialized) return;
    await _plugin.cancel(idDiaria);
  }

  /// No-op: los recordatorios automáticos de cobro los decide Supabase + FCM.
  Future<void> checkAndNotifyIfNeeded({bool force = false}) async {}

  Future<void> showTestNotification() async {
    // Misma prioridad/canal que convocatorias (el push remoto usa este canal).
    await _plugin.show(
      idDeudores,
      await _tr('notifTestTitle'),
      await _tr('notifTestBody'),
      await _convocatoriaDetails(),
      payload: payloadRecordatorio,
    );
  }

  Future<NotificationAppLaunchDetails?> getLaunchDetails() async {
    return _plugin.getNotificationAppLaunchDetails();
  }

  Future<NotificationDetails> _convocatoriaDetails() async {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelConvocatoriaId,
        await _tr('notifChannelConvocatoriaName'),
        channelDescription: await _tr('notifChannelConvocatoriaDesc'),
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  /// Notificación local cuando te convocan (mismo dispositivo).
  /// Push a otros teléfonos usa FCM vía [PushNotificationService].
  Future<void> showConvocatoriaInvitacion({
    required int partidoId,
    required DateTime fecha,
    required int horasLimite,
    String? titulo,
    String? cuerpo,
  }) async {
    if (!_initialized) return;
    await requestPermissions();

    final id = idConvocatoriaBase + (partidoId % 9000);
    await _plugin.show(
      id,
      titulo ?? await _tr('notifConvocadoTitle'),
      cuerpo ??
          await _tr(
            'notifConvocadoBody',
            params: {
              'date': formatDiaCompleto(fecha),
              'hours': '$horasLimite',
            },
          ),
      await _convocatoriaDetails(),
      payload: '$payloadConvocatoriaPrefix$partidoId',
    );
  }

  /// Abre la pantalla de respuesta a convocatoria (desde push o local).
  Future<void> openConvocatoria(int partidoId) async {
    await _abrirConvocatoria(partidoId, soloSiPendiente: true);
  }

  Future<void> openCancelacion(int partidoId) async {
    await _abrirCancelacion(partidoId);
  }

  Future<void> showPromocionTitular({
    required int partidoId,
    required DateTime fecha,
    required int horasLimite,
  }) async {
    await showConvocatoriaInvitacion(
      partidoId: partidoId,
      fecha: fecha,
      horasLimite: horasLimite,
    );
  }

  /// Recordatorio de plazo o aviso de vencimiento (mismo destino: responder).
  Future<void> showConvocatoriaMensaje({
    required int partidoId,
    required String titulo,
    required String cuerpo,
    int idOffset = 0,
    bool esCancelacion = false,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + idOffset + (partidoId % 8000);
    final prefix =
        esCancelacion ? payloadCancelacionPrefix : payloadConvocatoriaPrefix;
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      await _convocatoriaDetails(),
      payload: '$prefix$partidoId',
    );
  }

  /// Notificación local al organizador cuando un jugador responde.
  Future<void> showRespuestaConvocatoriaOrganizador({
    required int partidoId,
    required String titulo,
    required String cuerpo,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + 1000 + (partidoId % 8000);
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      await _convocatoriaDetails(),
      payload: '$payloadOrganizadorPartidoPrefix$partidoId',
    );
  }



  Future<void> openOrganizerHomePagos() async {
    await _abrirOrganizerHomePagos();
  }

  Future<void> openPartidoOrganizador(int partidoId) async {
    await _abrirPartidoOrganizador(partidoId);
  }

  Future<void> openMisCobros() async {
    await _abrirMisCobros();
  }

  /// Notificación de cobro de partido al jugador.
  Future<void> showCobroPartido({
    required int partidoId,
    required String titulo,
    required String cuerpo,
    String? detalle,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + 2000 + (partidoId % 7000);
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      await _convocatoriaDetails(),
      payload: '$payloadCobroPrefix$partidoId',
    );
  }

  /// Organizador: comprobante pendiente de validación.
  Future<void> showComprobantePendiente({
    required int partidoId,
    required int detalleId,
    required String titulo,
    required String cuerpo,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + 3000 + (detalleId % 6000);
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      await _convocatoriaDetails(),
      payload: '$payloadComprobantePrefix$partidoId:$detalleId',
    );
  }

  void showInAppSnack(
    String message, {
    BuildContext? context,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 5),
  }) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration,
    );
    final global = scaffoldMessengerKey?.currentState;
    if (global != null) {
      global.showSnackBar(snackBar);
      return;
    }
    if (context != null) {
      final local = ScaffoldMessenger.maybeOf(context);
      local?.showSnackBar(snackBar);
    }
  }

  /// Jugador: comprobante rechazado por el organizador.
  Future<void> showComprobanteRechazado({
    required int partidoId,
    required String titulo,
    required String cuerpo,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + 2500 + (partidoId % 6500);
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      await _convocatoriaDetails(),
      payload: '$payloadCobroPrefix$partidoId',
    );
  }

  /// Payload al abrir la app desde una notificación.
  /// Android/hot restart a veces reenvían el mismo launch: lo consumimos una vez.
  Future<void> handleLaunchPayload(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    if (_launchPayloadHandledThisSession) return;
    if (await _wasLaunchPayloadHandledRecently(payload)) {
      _launchPayloadHandledThisSession = true;
      return;
    }
    _launchPayloadHandledThisSession = true;
    await _markLaunchPayloadHandled(payload);

    if (payload == payloadRecordatorio) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _abrirRecordatorioDeudores();
    } else if (payload.startsWith(payloadCobroPrefix)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      appLog('FCM_NAV_RECEIVED type=local_cobro');
      await _abrirMisCobros();
    } else if (payload.startsWith(payloadComprobantePrefix)) {
      await _abrirOrganizerHomePagos();
    } else if (payload.startsWith(payloadOrganizadorPartidoPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadOrganizadorPartidoPrefix.length),
      );
      if (id != null) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _abrirPartidoOrganizador(id);
      }
    } else if (payload.startsWith(payloadCancelacionPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadCancelacionPrefix.length),
      );
      if (id != null) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _abrirCancelacion(id);
      }
    } else if (payload.startsWith(payloadConvocatoriaPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadConvocatoriaPrefix.length),
      );
      if (id != null) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        // Solo si aún debe responder (no reabrir convocatorias ya contestadas).
        await _abrirConvocatoria(id, soloSiPendiente: true);
      }
    }
  }

  Future<bool> _wasLaunchPayloadHandledRecently(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLaunchPayload);
    if (last != payload) return false;
    final at = prefs.getInt(_prefsLaunchAt) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age < const Duration(minutes: 30).inMilliseconds;
  }

  Future<void> _markLaunchPayloadHandled(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLaunchPayload, payload);
    await prefs.setInt(
      _prefsLaunchAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _abrirCancelacion(int partidoId) async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!ctx.mounted) return;
    await PartidoCanceladoPopupFlow.mostrarPartido(
      ctx,
      partidoId: partidoId,
    );
  }

  Future<void> _abrirConvocatoria(
    int partidoId, {
    bool soloSiPendiente = false,
  }) async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final repos = _repos;
    if (repos == null) {
      _snackReposUnavailable(ctx);
      return;
    }
    MiConvocatoria? conv = await repos.getMiConvocatoria(partidoId);

    if (conv == null) {
      final pendientes = await MisInvitacionesPanel.cargarPendientes(repos);
      for (final c in pendientes) {
        if (c.entry.partidoId == partidoId) {
          conv = c;
          break;
        }
      }
    }

    if (conv == null) {
      if (ctx.mounted && !soloSiPendiente) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(ctx.l10n.tr('convocatoriaNotFoundSnack'))),
        );
      }
      return;
    }

    // Ya respondió / suplente: no empujar la pantalla al arrancar ni por error.
    if (soloSiPendiente && !conv.requiereRespuesta) return;

    if (ctx.mounted) {
      await Navigator.of(ctx, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => ResponderConvocatoriaScreen(
            partidoId: partidoId,
            convocatoria: conv,
          ),
        ),
      );
    }
  }

  Future<void> _abrirMisCobros() async {
    if (_tryOpenMisCobros()) return;
    _pendingNavigation = PendingNavigation.misCobros;
    appLog('FCM_NAV_PENDING');
  }

  /// Prefer player tab; nunca el panel de cobros del organizador.
  /// Si no hay callback de jugador, hace push de [MisCobrosScreen].
  bool _tryOpenMisCobros() {
    final playerCb = onNavigatePlayerMisCobros;
    if (playerCb != null) {
      final ctx = navigatorKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).popUntil((route) => route.isFirst);
      }
      playerCb();
      AppRepositories.notifyDataChanged();
      appLog('FCM_NAV_EXECUTED');
      return true;
    }

    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) {
      appLog('FCM_NAV_NO_CONTEXT');
      return false;
    }

    Navigator.of(ctx, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const MisCobrosScreen()),
    );
    AppRepositories.notifyDataChanged();
    appLog('FCM_NAV_EXECUTED');
    return true;
  }

  Future<void> _abrirOrganizerHomePagos() async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 400));
    Navigator.of(ctx).popUntil((route) => route.isFirst);
    onNavigateOrganizerHome?.call();
    AppRepositories.notifyDataChanged();
  }


  Future<void> _abrirPartidoOrganizador(int partidoId) async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    await Navigator.of(ctx, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => OrganizarPartidoScreen(partidoId: partidoId),
      ),
    );
  }

  Future<void> _abrirRecordatorioDeudores() async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final l10n = ctx.l10n;

    final repos = _repos;
    if (repos == null) {
      _snackReposUnavailable(ctx);
      return;
    }

    final dias = await _prefs.recordatorioDias;
    final deudores = await repos.getDeudoresVencidos(dias);
    if (deudores.isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('noUnpaidPlayersDeadline'))),
        );
      }
      return;
    }

    if (ctx.mounted) {
      await RecordatorioDeudoresSheet.show(
        ctx,
        resumenes: deudores,
        titulo: l10n.tr('unpaidPlayersTitle'),
        subtitulo: l10n.tr(
          dias == 1 ? 'debtOlderThanDay' : 'debtOlderThanDays',
          params: {'days': '$dias'},
        ),
      );
    }
  }
}
