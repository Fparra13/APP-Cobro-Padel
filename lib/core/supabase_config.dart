import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuración de Supabase.
/// Valores por defecto del proyecto; puedes sobreescribir con --dart-define al compilar.
class SupabaseConfig {
  SupabaseConfig._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://efcfxfcypdsrmbultnkl.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmY2Z4ZmN5cGRzcm1idWx0bmtsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2MTAxMTEsImV4cCI6MjA5ODE4NjExMX0.yFws6pdZnXQLbkMiGrhHVkPBKArZ03Q4Sm7XtlujUho',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
      ),
    );
  }

  /// Scheme de deep links de la app (magic link + invitaciones).
  static const deepLinkScheme = 'kloovi';

  /// URL de redirect para magic link (registrar también en Supabase Dashboard).
  static const authRedirectUrl = '$deepLinkScheme://login-callback';

  /// Deep link de invitación a una convocatoria (`kloovi://invite/{partidoId}`).
  static String inviteDeepLink(int partidoId) =>
      '$deepLinkScheme://invite/$partidoId';

  /// Client ID tipo **Web** de Google Cloud (obligatorio para ID token / Supabase).
  /// `--dart-define=GOOGLE_WEB_CLIENT_ID=....apps.googleusercontent.com`
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  /// Client ID tipo **iOS** (solo iOS). Misma consola Google Cloud.
  /// `--dart-define=GOOGLE_IOS_CLIENT_ID=....apps.googleusercontent.com`
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isGoogleSignInConfigured => googleWebClientId.isNotEmpty;
}
