import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/offline/offline_screen_loader.dart';
import 'package:matchpay/offline/offline_snapshot_store.dart';
import 'package:matchpay/offline/player_loader.dart';
import 'package:matchpay/offline/player_snapshot.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('matchpay_player_loader_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('loadPlayerHome', () {
    test('fetch exitoso retorna live', () async {
      const data = PlayerHomeData(
        convocatorias: [],
        deudas: [],
        perfil: null,
        misStats: null,
        partidosJugados: [],
        historialSaldo: [],
        saldosPorPartido: {},
      );

      final result = await loadPlayerHome(
        snapshotStore: null,
        fetchOverride: () async => data,
      );

      expect(result.source, OfflineScreenLoadSource.live);
      expect(result.data, isNotNull);
    });

    test('fallo de red con snapshot usa offlineCache', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      const data = PlayerHomeData(
        convocatorias: [],
        deudas: [],
        perfil: null,
        misStats: null,
        partidosJugados: [],
        historialSaldo: [],
        saldosPorPartido: {},
      );
      await store.save(playerHomeSnapshotKey, data.toJson());

      final result = await loadPlayerHome(
        snapshotStore: store,
        fetchOverride: () async => throw const SocketException('sin red'),
      );

      expect(result.source, OfflineScreenLoadSource.offlineCache);
      expect(result.data, isNotNull);
    });
  });

  group('loadPlayerJugadorFicha', () {
    test('round-trip snapshot por jugadorKey', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      const key = 'abc-123';
      final data = PlayerJugadorFichaData(
        jugador: Jugador(
          nombre: 'Pepe',
          activo: true,
          email: 'pepe@test.com',
          createdAt: DateTime(2025, 6, 1),
          supabaseId: key,
        ),
        historial: [],
        pendientes: [],
        partidosJugados: 3,
        partidosPagados: 2,
      );
      await store.save(playerJugadorFichaSnapshotKey(key), data.toJson());

      final result = await loadPlayerJugadorFicha(
        jugadorKey: key,
        snapshotStore: store,
        fetchOverride: () async => throw const SocketException('sin red'),
      );

      expect(result.source, OfflineScreenLoadSource.offlineCache);
      expect(result.data?.jugador.nombre, 'Pepe');
      expect(result.data?.partidosJugados, 3);
    });
  });
}
