import 'package:flutter/foundation.dart';

/// Logs solo en debug. Nunca loguear emails, tokens ni PII en producción.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
