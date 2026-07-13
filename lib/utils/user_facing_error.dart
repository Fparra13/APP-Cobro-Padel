import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/network_errors.dart';
import '../offline/offline_exceptions.dart';

typedef Tr = String Function(String key, {Map<String, String> params});

/// Mensaje seguro para mostrar al usuario (sin URLs, códigos ni stack traces).
String userFacingError(
  Object error, {
  required Tr tr,
}) {
  if (error is OfflineWriteBlockedException ||
      error.toString().contains('OfflineWriteBlockedException')) {
    return tr('offlineWriteBlocked');
  }
  if (isNetworkError(error)) {
    return tr('connectionRequired');
  }

  if (error is PostgrestException) {
    final code = error.code;
    final msg = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
        .toLowerCase();
    if (msg.contains('cupo_lleno')) {
      return tr('errorCupoLleno');
    }
    if (msg.contains('datos_inconsistentes')) {
      return tr('errorDatosInconsistentes');
    }
    if (msg.contains('monto_invalido')) {
      return tr('errorMontoInvalido');
    }
    if (msg.contains('plazo_vencido')) {
      return tr('errorPlazoVencido');
    }
    if (msg.contains('convocatoria_cerrada') ||
        msg.contains('convocatoria_expirada')) {
      return tr('errorConvocatoriaCerrada');
    }
    if (msg.contains('suplente_no_responde')) {
      return tr('errorSuplenteNoResponde');
    }
    if (msg.contains('respuesta_no_permitida')) {
      return tr('errorRespuestaNoPermitida');
    }
    if (code == '42501' || code == 'PGRST301') {
      return tr('errorPermissionDenied');
    }
    if (code == '23505') {
      return tr('playerDuplicateContact');
    }
    return tr('errorGeneric');
  }

  final msg = error.toString().toLowerCase();
  if (msg.contains('cupo_lleno')) {
    return tr('errorCupoLleno');
  }
  if (msg.contains('datos_inconsistentes')) {
    return tr('errorDatosInconsistentes');
  }
  if (msg.contains('monto_invalido')) {
    return tr('errorMontoInvalido');
  }
  if (msg.contains('plazo_vencido')) {
    return tr('errorPlazoVencido');
  }
  if (msg.contains('convocatoria_cerrada') ||
      msg.contains('convocatoria_expirada')) {
    return tr('errorConvocatoriaCerrada');
  }
  if (msg.contains('suplente_no_responde')) {
    return tr('errorSuplenteNoResponde');
  }
  if (msg.contains('respuesta_no_permitida')) {
    return tr('errorRespuestaNoPermitida');
  }
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
