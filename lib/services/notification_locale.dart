import '../core/app_settings_controller.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import '../l10n/translation_maps.dart';

/// Resuelve idioma para notificaciones (local o push) y traduce textos.
class NotificationLocale {
  NotificationLocale._();

  static String tr(
    String languageCode,
    String key, {
    Map<String, String> params = const {},
  }) =>
      TranslationMaps.lookup(languageCode, key, params: params);

  static Future<String> currentLanguageCode() =>
      AppSettingsController.readLanguageCode();

  static Future<String> trCurrent(
    String key, {
    Map<String, String> params = const {},
  }) async {
    return tr(await currentLanguageCode(), key, params: params);
  }

  /// Idioma preferido del perfil remoto; si no hay, el del dispositivo/app.
  static Future<String> forUser(String? userId) async {
    if (userId != null &&
        userId.isNotEmpty &&
        SupabaseConfig.isConfigured) {
      try {
        final row = await SupabaseHelpers.client
            .from('profiles')
            .select('preferred_locale')
            .eq('id', userId)
            .maybeSingle();
        final raw = row?['preferred_locale']?.toString().trim();
        if (raw != null && raw.isNotEmpty) {
          return raw.split('_').first;
        }
      } catch (_) {}
    }
    return currentLanguageCode();
  }
}
