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

  /// URL de redirect para magic link (registrar también en Supabase Dashboard).
  static const authRedirectUrl = 'matchpay://login-callback';
}
