import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../repositories/partido_repository.dart';
import '../widgets/recordatorio_deudores_sheet.dart';
import 'preferences_service.dart';

/// Notificaciones locales para avisar de jugadores impagos.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const channelId = 'recordatorio_deudores';
  static const channelName = 'Recordatorios de cobro';
  static const payloadRecordatorio = 'recordatorio_deudores';
  static const idDeudores = 1001;
  static const idDiaria = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _partidoRepo = PartidoRepository();
  final _prefs = PreferencesService();

  GlobalKey<NavigatorState>? navigatorKey;
  bool _initialized = false;

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
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: 'Avisos de jugadores con pagos pendientes',
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == payloadRecordatorio) {
      _abrirRecordatorioDeudores();
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

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Avisos de jugadores con pagos pendientes',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
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

    await _plugin.zonedSchedule(
      idDiaria,
      '🎾 Pádel Cobro',
      'Revisa si hay jugadores con pagos pendientes',
      _proximaHora(hora, minuto),
      _details(),
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
    final deudores = await _partidoRepo.getDeudoresVencidos(dias);
    if (deudores.isEmpty) return;

    if (!force) {
      final hoy = DateTime.now().toIso8601String().substring(0, 10);
      final ultima = await _prefs.recordatorioUltimaFecha;
      if (ultima == hoy) return;
      await _prefs.saveRecordatorioUltimaFecha(hoy);
    }

    final n = deudores.length;
    final titulo = n == 1
        ? '1 jugador sin pagar'
        : '$n jugadores sin pagar';
    final cuerpo = n == 1
        ? '${deudores.first.jugador.nombre} lleva más de $dias día${dias == 1 ? '' : 's'} sin pagar. Toca para enviar recordatorio.'
        : 'Hay $n jugadores con deuda de más de $dias días. Toca para enviar recordatorios.';

    await _plugin.show(
      idDeudores,
      titulo,
      cuerpo,
      _details(),
      payload: payloadRecordatorio,
    );
  }

  Future<void> showTestNotification() async {
    await _plugin.show(
      idDeudores,
      '🎾 Recordatorio de prueba',
      'Las notificaciones están activas. Toca para abrir recordatorios.',
      _details(),
      payload: payloadRecordatorio,
    );
  }

  Future<NotificationAppLaunchDetails?> getLaunchDetails() async {
    return _plugin.getNotificationAppLaunchDetails();
  }

  Future<void> handleLaunchPayload(String? payload) async {
    if (payload == payloadRecordatorio) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _abrirRecordatorioDeudores();
    }
  }

  Future<void> _abrirRecordatorioDeudores() async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final dias = await _prefs.recordatorioDias;
    final deudores = await _partidoRepo.getDeudoresVencidos(dias);
    if (deudores.isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('No hay jugadores impagos que cumplan el plazo'),
          ),
        );
      }
      return;
    }

    if (ctx.mounted) {
      await RecordatorioDeudoresSheet.show(
        ctx,
        resumenes: deudores,
        titulo: 'Jugadores impagos',
        subtitulo: 'Deuda de más de $dias día${dias == 1 ? '' : 's'}',
      );
    }
  }
}
