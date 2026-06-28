import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

/// Utilidades compartidas para repositorios remotos Supabase.
class SupabaseHelpers {
  SupabaseHelpers._();

  static SupabaseClient get client {
    if (!SupabaseConfig.isConfigured) {
      throw Exception('Supabase no está configurado');
    }
    return Supabase.instance.client;
  }

  static String? get currentUserId => client.auth.currentUser?.id;

  static Future<T> guard<T>(String operacion, Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw Exception('$operacion: ${e.message}');
    } catch (e) {
      throw Exception('$operacion: $e');
    }
  }
}
