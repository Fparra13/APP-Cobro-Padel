import 'package:flutter/foundation.dart' show visibleForTesting;

/// Logs de diagnóstico Billing visibles en release (logcat).
///
/// Prefijo fijo [prefix]. Nunca registrar tokens, JWT, headers ni bodies.
abstract final class KlooviBillingDiag {
  KlooviBillingDiag._();

  static const prefix = 'KLOOVI_BILLING_DIAG';

  /// Sink opcional para tests (no imprime secretos; solo fases/campos seguros).
  @visibleForTesting
  static void Function(String phase, Map<String, Object?> fields)? sinkForTests;

  /// Emite una línea `KLOOVI_BILLING_DIAG <phase> key=value ...`.
  static void log(String phase, [Map<String, Object?> fields = const {}]) {
    final safePhase = _sanitizeToken(phase);
    final safeFields = <String, Object?>{};
    for (final e in fields.entries) {
      final key = _sanitizeToken(e.key);
      if (_isForbiddenKey(key)) continue;
      safeFields[key] = _sanitizeValue(e.value);
    }
    sinkForTests?.call(
      safePhase,
      Map<String, Object?>.unmodifiable(safeFields),
    );

    final buf = StringBuffer('$prefix $safePhase');
    for (final e in safeFields.entries) {
      buf.write(' ${e.key}=${e.value}');
    }
    // ignore: avoid_print — debe verse en release / adb logcat
    print(buf.toString());
  }

  /// Tipo de error sin mensaje (evita filtrar tokens en excepciones).
  static String sanitizeError(Object error) {
    return error.runtimeType.toString();
  }

  static bool _isForbiddenKey(String key) {
    final k = key.toLowerCase();
    return k.contains('token') ||
        k.contains('jwt') ||
        k.contains('authorization') ||
        k.contains('password') ||
        k.contains('secret') ||
        k.contains('apikey') ||
        k.contains('api_key') ||
        k.contains('verification') ||
        k.contains('purchase_token') ||
        k.contains('body');
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null) return null;
    if (value is bool || value is num) return value;
    if (value is String) return _sanitizeToken(value);
    return value.runtimeType.toString();
  }

  static String _sanitizeToken(String raw) {
    // Evita pegar cadenas largas tipo JWT/token por accidente.
    final t = raw.trim();
    if (t.length > 80) return '${t.substring(0, 24)}…len=${t.length}';
    if (t.contains('.') && t.length > 40) {
      // Heurística JWT-ish
      return 'redacted_len=${t.length}';
    }
    return t.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  }
}
