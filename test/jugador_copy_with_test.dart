import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/jugador.dart';

void main() {
  test('copyWith preserves appLastSeenAt so tieneMatchPayApp stays true', () {
    final base = Jugador(
      nombre: 'Ana',
      appLastSeenAt: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final withSaldo = base.copyWith(saldoAcumulado: 12.5);
    expect(withSaldo.saldoAcumulado, 12.5);
    expect(withSaldo.appLastSeenAt, DateTime.utc(2026, 1, 1));
    expect(withSaldo.tieneMatchPayApp, isTrue);
  });

  test('copyWith can clear appLastSeenAt explicitly', () {
    final base = Jugador(
      nombre: 'Ana',
      appLastSeenAt: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final cleared = base.copyWith(clearAppLastSeenAt: true);
    expect(cleared.appLastSeenAt, isNull);
    expect(cleared.tieneMatchPayApp, isFalse);
  });

  test('tieneMatchPayApp false without appLastSeenAt', () {
    final base = Jugador(
      nombre: 'Ana',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(base.tieneMatchPayApp, isFalse);
  });

  test('fromSupabaseMap ignores fcm_token and uses app_last_seen_at', () {
    final j = Jugador.fromSupabaseMap({
      'id': 'u1',
      'nombre': 'Ana',
      'activo': true,
      'fcm_token': 'should-be-ignored',
      'app_last_seen_at': '2026-01-02T00:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(j.tieneMatchPayApp, isTrue);
    expect(j.appLastSeenAt, isNotNull);
  });

  test('fromSupabaseMap usa_app without timestamp still marks app user', () {
    final j = Jugador.fromSupabaseMap({
      'id': 'u1',
      'nombre': 'Ana',
      'activo': true,
      'usa_app': true,
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(j.tieneMatchPayApp, isTrue);
  });
}
