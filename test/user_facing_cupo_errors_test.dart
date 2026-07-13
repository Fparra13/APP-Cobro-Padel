import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/utils/user_facing_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  String tr(String key, {Map<String, String> params = const {}}) => key;

  test('mapea cupo_lleno y plazo_vencido desde PostgrestException', () {
    expect(
      userFacingError(
        PostgrestException(message: 'cupo_lleno', code: 'P0001'),
        tr: tr,
      ),
      'errorCupoLleno',
    );
    expect(
      userFacingError(
        PostgrestException(message: 'plazo_vencido', code: 'P0001'),
        tr: tr,
      ),
      'errorPlazoVencido',
    );
    expect(
      userFacingError(
        Exception('Exception: convocatoria_cerrada'),
        tr: tr,
      ),
      'errorConvocatoriaCerrada',
    );
  });
}
