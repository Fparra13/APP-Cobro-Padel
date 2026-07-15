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

  test(
    'confirmaciones usan historial, no solo convocatorias vigentes',
    () {
      final now = DateTime(2026, 7, 14);
      final stats = buildMisEstadisticasDesdeHome(
        uid: 'uid-1',
        perfil: Jugador(
          supabaseId: 'uid-1',
          nombre: 'Francisco',
          createdAt: now,
        ),
        partidosJugados: [
          DetallePartido(
            partidoId: 1,
            jugadorSupabaseId: 'uid-1',
            total: 6000,
            pagado: true,
            fechaPartido: now,
          ),
        ],
        // get_mis_convocatorias_jugador solo trae vigentes → a menudo 0/1.
        convocatorias: const [],
        confirmacionesHistoricas: 12,
      );

      expect(stats, isNotNull);
      expect(stats!.convocatoriasConfirmadas, 12);
    },
  );
}
