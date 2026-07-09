/// Parsing defensivo de valores JSON de Supabase.
class SupabaseParse {
  SupabaseParse._();

  static double toDouble(dynamic value, {double fallback = 0}) =>
      (value is num) ? value.toDouble() : fallback;

  static int toInt(dynamic value, {int fallback = 0}) =>
      (value is num) ? value.toInt() : fallback;

  static String asString(dynamic value, {String fallback = ''}) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty) return fallback;
    return s;
  }

  static String? toStringOrNull(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  static DateTime toDateTime(dynamic value, {DateTime? fallback}) {
    if (value == null) return fallback ?? DateTime.now();
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return fallback ?? DateTime.now();
    }
  }

  /// Serializa un [DateTime] local (p. ej. del date picker) a timestamptz UTC.
  static String toTimestamptz(DateTime value) {
    final instant = value.isUtc ? value : value.toUtc();
    return instant.toIso8601String();
  }

  static bool toBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return fallback;
  }

  /// Embed de relación (Map o List con un solo elemento).
  static Map<String, dynamic>? mapEmbed(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  /// Extrae `nombre` de un embed `profiles` (Map o List por join).
  static String? nombrePerfilEmbed(dynamic profile) {
    final map = mapEmbed(profile);
    return map == null ? null : toStringOrNull(map['nombre']);
  }
}
