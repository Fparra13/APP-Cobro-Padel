import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:matchpay/domain/cobro_logic.dart';
import 'package:matchpay/utils/user_facing_error.dart';

void main() {
  String tr(String key, {Map<String, String> params = const {}}) => key;

  test('DatosInconsistentesException maps to errorDatosInconsistentes', () {
    expect(
      userFacingError(
        const DatosInconsistentesException('Datos inconsistentes: falta snapshot'),
        tr: tr,
      ),
      'errorDatosInconsistentes',
    );
  });

  test('network errors map to connectionRequired', () {
    expect(
      userFacingError(Exception('SocketException: Failed host lookup'),
          tr: tr),
      'connectionRequired',
    );
  });

  test('permission errors map to errorPermissionDenied', () {
    expect(
      userFacingError(
        const PostgrestException(message: 'denied', code: '42501'),
        tr: tr,
      ),
      'errorPermissionDenied',
    );
  });

  test('generic errors never expose raw message', () {
    final msg = userFacingError(
      Exception('PostgrestException(code=PGRST116, details=...)'),
      tr: tr,
    );
    expect(msg, 'errorGeneric');
    expect(msg.contains('PGRST'), isFalse);
    expect(msg.contains('Postgrest'), isFalse);
  });
}
