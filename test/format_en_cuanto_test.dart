import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchpay/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  setUp(() {
    MoneyFormatConfig.dateLocale = 'es';
  });

  test('viernes 23:50 → domingo 20:00 no dice mañana', () {
    // 2026-07-24 = viernes
    final now = DateTime(2026, 7, 24, 23, 50);
    final encuentro = DateTime(2026, 7, 26, 20, 0);
    final text = formatEnCuanto(encuentro, now: now);
    expect(text.toLowerCase().contains('mañana'), isFalse);
    expect(text.toLowerCase(), contains('domingo'));
    expect(text, contains('20:00'));
  });

  test('encuentro sábado siguiente muestra mañana', () {
    final now = DateTime(2026, 7, 24, 23, 50); // viernes
    final encuentro = DateTime(2026, 7, 25, 20, 0); // sábado
    final text = formatEnCuanto(encuentro, now: now);
    expect(text.toLowerCase(), contains('mañana'));
    expect(text, contains('20:00'));
  });

  test('encuentro hoy muestra hoy', () {
    final now = DateTime(2026, 7, 24, 10, 0);
    final encuentro = DateTime(2026, 7, 24, 20, 0);
    final text = formatEnCuanto(encuentro, now: now);
    expect(text.toLowerCase(), contains('hoy'));
    expect(text, contains('20:00'));
  });
}
