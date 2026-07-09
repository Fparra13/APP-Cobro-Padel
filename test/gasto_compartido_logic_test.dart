import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/gasto_compartido_logic.dart';

void main() {
  group('GastoCompartidoLogic.participantesReparto', () {
    test('repartoEntreTodos divide entre todos los asistentes actuales', () {
      final participantes = GastoCompartidoLogic.participantesReparto(
        participantesExplicitos: {'a'},
        asistentes: {'a', 'b', 'c', 'd'},
        repartoEntreTodos: true,
        sinParticipantesExplicito: false,
        monto: 40000,
      );
      expect(participantes, {'a', 'b', 'c', 'd'});
    });

    test('selección explícita parcial cuando repartoEntreTodos es false', () {
      final participantes = GastoCompartidoLogic.participantesReparto(
        participantesExplicitos: {'a', 'b'},
        asistentes: {'a', 'b', 'c', 'd'},
        repartoEntreTodos: false,
        sinParticipantesExplicito: false,
        monto: 20000,
      );
      expect(participantes, {'a', 'b'});
    });

    test('ninguno explícito no reparte', () {
      final participantes = GastoCompartidoLogic.participantesReparto(
        participantesExplicitos: {},
        asistentes: {'a', 'b'},
        repartoEntreTodos: false,
        sinParticipantesExplicito: true,
        monto: 10000,
      );
      expect(participantes, isEmpty);
    });
  });

  group('GastoCompartidoLogic.cuotaJugador', () {
    test('divide el monto entre participantes efectivos', () {
      expect(
        GastoCompartidoLogic.cuotaJugador(
          montoTotal: 15000,
          participantes: {'a', 'b'},
          jugadorId: 'a',
        ),
        7500,
      );
      expect(
        GastoCompartidoLogic.cuotaJugador(
          montoTotal: 15000,
          participantes: {'a', 'b'},
          jugadorId: 'b',
        ),
        7500,
      );
    });
  });
}
