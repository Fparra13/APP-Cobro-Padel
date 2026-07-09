import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/supabase_parse.dart';

void main() {
  test('toTimestamptz convierte hora local a UTC para Supabase', () {
    // Martes 7 jul 23:29 Chile (UTC-4) → partido miércoles 8 jul 00:33 local.
    final local = DateTime(2026, 7, 8, 0, 33);
    final stored = SupabaseParse.toTimestamptz(local);

    expect(stored, contains('T04:33:00'));
    expect(stored.endsWith('Z') || stored.contains('+'), isTrue);

    final read = SupabaseParse.toDateTime(stored);
    expect(read.year, 2026);
    expect(read.month, 7);
    expect(read.day, 8);
    expect(read.hour, 0);
    expect(read.minute, 33);
  });

  test('toDateTime normaliza timestamptz UTC a hora local', () {
    final read = SupabaseParse.toDateTime('2026-07-08T04:33:00+00:00');
    expect(read.hour, 0);
    expect(read.minute, 33);
  });
}
