import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_log.dart';

/// Handlers oficiales de Crashlytics (FlutterError + PlatformDispatcher + Zone).
///
/// Solo se activa si Firebase ya está inicializado ([FirebaseConfig.ensureInitialized]).
class CrashlyticsBootstrap {
  CrashlyticsBootstrap._();

  static bool _installed = false;

  /// Configura recolección y handlers de errores no capturados.
  static Future<void> install() async {
    if (_installed || Firebase.apps.isEmpty) return;

    // En debug no spameamos el dashboard; en release sí.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );

    FlutterError.onError = (FlutterErrorDetails details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    _installed = true;
  }

  /// Errores asíncronos fuera del framework (callback de [runZonedGuarded]).
  static void recordZoneError(Object error, StackTrace stack) {
    if (Firebase.apps.isEmpty) {
      appLog('Uncaught zone error: $error\n$stack');
      return;
    }
    unawaited(
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
    );
  }

  /// Paso 3 de la guía oficial: fuerza una excepción de prueba.
  /// Activa recolección aunque estés en debug para que el informe llegue.
  static Future<void> forceTestException() async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase no inicializado (faltan dart-define o init)');
    }
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    await FirebaseCrashlytics.instance.log('Kloovi Crashlytics test');
    throw Exception('Crashlytics test exception');
  }
}
