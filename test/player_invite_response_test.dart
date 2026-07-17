import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/player_invite_response.dart';

void main() {
  group('resumenDesdeEstadosConfirmacion', () {
    test('cuenta recibidas, respondidas y confirmadas', () {
      final r = resumenDesdeEstadosConfirmacion([
        'confirmado',
        'rechazado',
        'invitado',
        'no_respondio',
        'confirmado',
      ]);
      expect(r.recibidas, 5);
      expect(r.respondidas, 3);
      expect(r.confirmadas, 2);
      expect(r.porcentajeRespuesta, 60);
    });

    test('sin invitaciones → 0%', () {
      expect(resumenDesdeEstadosConfirmacion(const []).porcentajeRespuesta, 0);
    });
  });

  group('resolvePrideSecondaryMetric', () {
    test('prioriza % respuesta si hay invitaciones', () {
      final m = resolvePrideSecondaryMetric(
        invitaciones: const MisInvitacionesResumen(
          recibidas: 4,
          respondidas: 3,
          confirmadas: 2,
        ),
        semanasJugando: 5,
      );
      expect(m.kind, PlayerPrideSecondaryKind.respuesta);
      expect(m.porcentaje, 75);
    });

    test('fallback a racha sin invitaciones', () {
      final m = resolvePrideSecondaryMetric(
        invitaciones: MisInvitacionesResumen.empty,
        semanasJugando: 3,
      );
      expect(m.kind, PlayerPrideSecondaryKind.racha);
      expect(m.semanas, 3);
    });

    test('vacío sin invitaciones ni racha', () {
      final m = resolvePrideSecondaryMetric(
        invitaciones: MisInvitacionesResumen.empty,
        semanasJugando: 1,
      );
      expect(m.kind, PlayerPrideSecondaryKind.vacio);
    });
  });
}
