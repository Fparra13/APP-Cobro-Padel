import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_logic.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/offline/offline_snapshot_codec.dart';

void main() {
  group('roster sync / offline fcm hygiene', () {
    test('estadoTrasEdicionConvocatoria preserves confirmado', () {
      expect(
        CobroLogic.estadoTrasEdicionConvocatoria(
          prevEstado: EstadoConfirmacion.confirmado,
          inputEstado: EstadoConfirmacion.invitado,
        ),
        EstadoConfirmacion.confirmado,
      );
    });

    test('offline snapshot does not persist fcm_token', () {
      final j = Jugador(
        supabaseId: 'u1',
        nombre: 'Ana',
        appLastSeenAt: DateTime.utc(2026, 3, 1),
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final json = jugadorToSnapshotJson(j);
      expect(json.containsKey('fcm_token'), isFalse);
      expect(json['app_last_seen_at'], isNotNull);

      final roundTrip = jugadorFromSnapshotJson({
        ...json,
        'fcm_token': 'stale-should-ignore',
      });
      expect(roundTrip.tieneMatchPayApp, isTrue);
      expect(roundTrip.appLastSeenAt, DateTime.utc(2026, 3, 1));
    });
  });
}
