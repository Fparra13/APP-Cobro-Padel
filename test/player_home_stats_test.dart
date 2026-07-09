import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/player_home_stats.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/models/jugador.dart';

void main() {
  test('buildMisEstadisticasDesdeHome usa partidos visibles al jugador', () {
    final now = DateTime(2026, 7, 1);
    final stats = buildMisEstadisticasDesdeHome(
      uid: 'uid-1',
      perfil: Jugador(
        supabaseId: 'uid-1',
        nombre: 'Catalina',
        createdAt: now,
      ),
      partidosJugados: [
        DetallePartido(
          partidoId: 1,
          jugadorSupabaseId: 'uid-1',
          total: 5000,
          pagado: true,
          fechaPartido: now,
        ),
        const DetallePartido(
          partidoId: 2,
          jugadorSupabaseId: 'uid-1',
          total: 4000,
          pagado: false,
          fechaPartido: null,
        ),
      ],
      convocatorias: const [],
    );

    expect(stats, isNotNull);
    expect(stats!.partidosJugados, 2);
    expect(stats.pagosAlDia, 1);
    expect(stats.partidosImpagos, 1);
  });
}
