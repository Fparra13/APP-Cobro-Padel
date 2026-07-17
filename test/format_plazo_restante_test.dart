import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/utils/formatters.dart';

void main() {
  test('formatPlazoRestante muestra minutos bajo 1 h', () {
    expect(
      formatPlazoRestante(const Duration(minutes: 45)),
      '45 min',
    );
  });

  test('formatPlazoRestante muestra horas y minutos', () {
    expect(
      formatPlazoRestante(const Duration(hours: 3, minutes: 20)),
      '3 h 20 min',
    );
  });
}
