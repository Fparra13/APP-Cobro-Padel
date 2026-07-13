import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../offline/offline_write_guard.dart';

/// Utilidades compartidas para repositorios remotos Supabase.
class SupabaseHelpers {
  SupabaseHelpers._();

  static final OfflineWriteGuard _writeGuard = OfflineWriteGuard();

  static SupabaseClient get client {
    if (!SupabaseConfig.isConfigured) {
      throw Exception('Supabase no está configurado');
    }
    return Supabase.instance.client;
  }

  static String? get currentUserId => client.auth.currentUser?.id;

  /// Texto legible de errores PostgREST (incl. RLS: code 42501).
  static String describeError(Object e, {String? operacion}) {
    final prefix = operacion != null ? '$operacion: ' : '';
    if (e is PostgrestException) {
      final parts = <String>[e.message];
      final code = e.code;
      if (code != null && code.isNotEmpty) parts.add('code=$code');
      if (e.details != null && e.details.toString().isNotEmpty) {
        parts.add('details=${e.details}');
      }
      final hint = e.hint;
      if (hint != null && hint.isNotEmpty) parts.add('hint=$hint');
      return '$prefix${parts.join(' · ')}';
    }
    if (e is Exception) return '$prefix${e.toString().replaceFirst('Exception: ', '')}';
    return '$prefix$e';
  }

  static Future<T> guard<T>(String operacion, Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception(describeError(e, operacion: operacion));
    }
  }

  /// Escrituras remotas: exige internet antes de tocar Supabase.
  static Future<T> write<T>(String operacion, Future<T> Function() fn) {
    return _writeGuard.run(() => guard(operacion, fn));
  }

  static Future<T> withTimeout<T>(
    Future<T> future, {
    Duration timeout = const Duration(seconds: 20),
    String? operacion,
  }) {
    return future.timeout(
      timeout,
      onTimeout: () {
        throw Exception(
          '${operacion ?? 'Operación'}: Tiempo de espera agotado '
          '(${timeout.inSeconds}s). Posible bloqueo RLS o problema de red en Supabase.',
        );
      },
    );
  }
}
