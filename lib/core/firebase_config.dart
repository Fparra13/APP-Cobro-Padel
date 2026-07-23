import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_log.dart';

/// Configuración Firebase (Core / FCM / Crashlytics).
///
/// 1. Crea proyecto en Firebase Console y app Android `com.matchpay.app`
/// 2. Descarga `google-services.json` → `android/app/google-services.json`
/// 3. Compila con --dart-define (valores en Project settings → General):
///    FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID
/// 4. En Supabase: secret FIREBASE_SERVICE_ACCOUNT (JSON cuenta de servicio)
/// 5. Despliega Edge Function: supabase functions deploy send-push
/// 6. Crashlytics: habilitar en Firebase Console; Analytics recomendado (breadcrumbs)
class FirebaseConfig {
  FirebaseConfig._();

  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );

  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );

  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );

  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  static bool get isConfigured =>
      !kIsWeb &&
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('Firebase no configurado (dart-define o flutterfire configure)');
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
    );
  }

  static String? lastInitError;

  static Future<bool> ensureInitialized() async {
    lastInitError = null;
    if (!isConfigured) {
      lastInitError = 'not_configured';
      return false;
    }
    if (Firebase.apps.isNotEmpty) return true;
    try {
      await Firebase.initializeApp(options: currentPlatform);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app' || Firebase.apps.isNotEmpty) return true;
      lastInitError = 'firebase:${e.code}:${e.message}';
      appLog('Firebase init: $lastInitError');
      return false;
    } catch (e) {
      // Auto-init nativo / carrera: la app puede existir pese al error.
      if (Firebase.apps.isNotEmpty) return true;
      final msg = e.toString();
      if (msg.contains('duplicate-app')) return true;
      lastInitError = 'init:$e';
      appLog('Firebase init: $lastInitError');
      return false;
    }
  }

  static Future<void> initialize() async {
    await ensureInitialized();
  }
}
