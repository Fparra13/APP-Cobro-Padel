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
import '../utils/formatters.dart';
import '../widgets/mis_invitaciones_panel.dart';
import '../widgets/recordatorio_deudores_sheet.dart';
import 'preferences_service.dart';

/// Notificaciones locales para avisar de jugadores impagos.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const channelId = 'recordatorio_deudores';
  static const channelConvocatoriaId = 'convocatorias';
  static const payloadRecordatorio = 'recordatorio_deudores';
  static const payloadConvocatoriaPrefix = 'convocatoria:';
  static const payloadOrganizadorPartidoPrefix = 'organizador_partido:';
  static const payloadCobroPrefix = 'cobro:';
  static const payloadComprobantePrefix = 'comprobante:';
  static const idDeudores = 1001;
  static const idDiaria = 1002;
  static const idConvocatoriaBase = 2000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _prefs = PreferencesService();

  AppRepositories get _repos => AppRepositories.active;

  GlobalKey<NavigatorState>? navigatorKey;
  bool _initialized = false;
  bool _launchPayloadHandledThisSession = false;
  VoidCallback? onNavigateOrganizerHome;
  VoidCallback? onNavigateOrganizerMisCobros;
  VoidCallback? onNavigatePlayerMisCobros;

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
  }) async {
    if (_initialized) return;
    navigatorKey = navKey;

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

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            await _tr('notifChannelRemindersName'),
            description: await _tr('notifChannelRemindersDesc'),
            importance: Importance.high,
          ),
        );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelConvocatoriaId,
            await _tr('notifChannelConvocatoriaName'),
            description: await _tr('notifChannelConvocatoriaDesc'),
            importance: Importance.max,
          ),
        );

    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == payloadRecordatorio) {
      _abrirRecordatorioDeudores();
    } else if (payload != null && payload.startsWith(payloadCobroPrefix)) {
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
        payload.startsWith(payloadConvocatoriaPrefix)) {
      final id = int.tryParse(
        payload.substring(payloadConvocatoriaPrefix.length),
      );
      if (id != null) {
        _abrirConvocatoria(id, soloSiPendiente: true);
      }
    }
  }

  Future<bool> requestPermissions() async {
    var granted = true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? false;
      await android.requestExactAlarmsPermission();
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

  Future<void> syncSchedule() async {
    if (!_initialized) return;

    final activo = await _prefs.recordatorioActivo;
    if (!activo) {
      await _plugin.cancel(idDiaria);
      return;
    }

    final hora = await _prefs.recordatorioHora;
    final minuto = await _prefs.recordatorioMinuto;
    final appName = await _tr('appName');

    await _plugin.zonedSchedule(
      idDiaria,
      appName,
      await _tr('notifDailyBody'),
      _proximaHora(hora, minuto),
      await _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payloadRecordatorio,
    );
  }

  tz.TZDateTime _proximaHora(int hora, int minuto) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hora,
      minuto,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Revisa deudores vencidos y muestra notificación (máx. 1 por día).
  Future<void> checkAndNotifyIfNeeded({bool force = false}) async {
    if (!_initialized) return;

    final activo = await _prefs.recordatorioActivo;
    if (!activo && !force) return;

    final dias = await _prefs.recordatorioDias;
    final deudores = await _repos.getDeudoresVencidos(dias);
    if (deudores.isEmpty) return;

    if (!force) {
      final hoy = DateTime.now().toIso8601String().substring(0, 10);
      final ultima = await _prefs.recordatorioUltimaFecha;
      if (ultima == hoy) return;
      await _prefs.saveRecordatorioUltimaFecha(hoy);
    }

    final n = deudores.length;
    final titulo = n == 1
        ? await _tr('notifOnePlayerUnpaidTitle')
        : await _tr('notifNPlayersUnpaidTitle', params: {'count': '$n'});
    final cuerpo = n == 1
        ? await _tr(
            dias == 1
                ? 'notifOnePlayerUnpaidBodyOneDay'
                : 'notifOnePlayerUnpaidBody',
            params: {
              'name': deudores.first.jugador.nombre,
              'days': '$dias',
            },
          )
        : await _tr(
            'notifNPlayersUnpaidBody',
            params: {'count': '$n', 'days': '$dias'},
          );

    await _plugin.show(
      idDeudores,
      titulo,
      cuerpo,
      await _details(),
      payload: payloadRecordatorio,
    );
  }

  Future<void> showTestNotification() async {
    await _plugin.show(
      idDeudores,
      await _tr('notifTestTitle'),
      await _tr('notifTestBody'),
      await _details(),
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

  Future<void> showPromocionTitular({
    required int partidoId,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + 500 + (partidoId % 8500);
    await _plugin.show(
      id,
      await _tr('notifPromocionTitle'),
      await _tr('notifPromocionBody'),
      await _convocatoriaDetails(),
      payload: '$payloadConvocatoriaPrefix$partidoId',
    );
  }

  /// Recordatorio de plazo o aviso de vencimiento (mismo destino: responder).
  Future<void> showConvocatoriaMensaje({
    required int partidoId,
    required String titulo,
    required String cuerpo,
    int idOffset = 0,
  }) async {
    if (!_initialized) return;
    await requestPermissions();
    final id = idConvocatoriaBase + idOffset + (partidoId % 8000);
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      await _convocatoriaDetails(),
      payload: '$payloadConvocatoriaPrefix$partidoId',
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

  Future<void> _abrirConvocatoria(
    int partidoId, {
    bool soloSiPendiente = false,
  }) async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final repos = _repos;
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
    final goToTab = onNavigateOrganizerMisCobros ?? onNavigatePlayerMisCobros;
    if (goToTab != null) {
      final ctx = navigatorKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).popUntil((route) => route.isFirst);
      }
      goToTab();
      AppRepositories.notifyDataChanged();
      return;
    }

    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    await Navigator.of(ctx, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const MisCobrosScreen()),
    );
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

    final dias = await _prefs.recordatorioDias;
    final deudores = await _repos.getDeudoresVencidos(dias);
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
