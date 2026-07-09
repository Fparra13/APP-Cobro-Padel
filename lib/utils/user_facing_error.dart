import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/network_errors.dart';

typedef Tr = String Function(String key, {Map<String, String> params});

/// Mensaje seguro para mostrar al usuario (sin URLs, códigos ni stack traces).
String userFacingError(
  Object error, {
  required Tr tr,
}) {
  if (isNetworkError(error)) {
    return tr('connectionRequired');
  }

  if (error is PostgrestException) {
    final code = error.code;
    if (code == '42501' || code == 'PGRST301') {
      return tr('errorPermissionDenied');
    }
    if (code == '23505') {
      return tr('playerDuplicateContact');
    }
    return tr('errorGeneric');
  }

  final msg = error.toString().toLowerCase();
  if (msg.contains('code=42501') ||
      msg.contains('permission_denied') ||
      msg.contains('permiso')) {
    return tr('errorPermissionDenied');
  }
  if (msg.contains('code=23505') || msg.contains('duplicate key')) {
    return tr('playerDuplicateContact');
  }
  if (msg.contains('storage') ||
      msg.contains('row-level security') ||
      msg.contains('code=403') ||
      msg.contains('unauthorized')) {
    return tr('errorPhotoUpload');
  }
  if (msg.contains('timeout') ||
      msg.contains('tiempo de espera agotado') ||
      msg.contains('timed out')) {
    return tr('errorTimeout');
  }

  if (msg.contains('supabase no está configurado')) {
    return tr('errorGeneric');
  }

  return tr('errorGeneric');
}
