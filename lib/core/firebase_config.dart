import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuración Firebase / FCM.
///
/// 1. Crea proyecto en Firebase Console y app Android `com.padelcobro.padel_cobro`
/// 2. Descarga `google-services.json` → `android/app/google-services.json`
/// 3. Compila con --dart-define (valores en Project settings → General):
///    FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID
/// 4. En Supabase: secret FIREBASE_SERVICE_ACCOUNT (JSON cuenta de servicio)
/// 5. Despliega Edge Function: supabase functions deploy send-push
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

  static Future<bool> ensureInitialized() async {
    if (!isConfigured) return false;
    if (Firebase.apps.isNotEmpty) return true;
    try {
      await Firebase.initializeApp(options: currentPlatform);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') return true;
      debugPrint('Firebase init: $e');
      return false;
    } catch (e) {
      debugPrint('Firebase init: $e');
      return false;
    }
  }

  static Future<void> initialize() async {
    await ensureInitialized();
  }
}
