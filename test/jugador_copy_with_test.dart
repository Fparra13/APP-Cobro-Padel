import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/jugador.dart';

void main() {
  test('copyWith preserves fcmToken so tieneMatchPayApp stays true', () {
    final base = Jugador(
      supabaseId: 'org-1',
      nombre: 'Organizador',
      fcmToken: 'token-abc',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final withSaldo = base.copyWith(saldoAcumulado: 12.5);

    expect(withSaldo.fcmToken, 'token-abc');
    expect(withSaldo.tieneMatchPayApp, isTrue);
    expect(withSaldo.saldoAcumulado, 12.5);
  });

  test('copyWith can clear fcmToken explicitly', () {
    final base = Jugador(
      supabaseId: 'j-1',
      nombre: 'Jugador',
      fcmToken: 'token-abc',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final cleared = base.copyWith(clearFcmToken: true);

    expect(cleared.fcmToken, isNull);
    expect(cleared.tieneMatchPayApp, isFalse);
  });
}
