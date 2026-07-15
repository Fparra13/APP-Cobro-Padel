import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_logic.dart';
import 'package:matchpay/models/cobros_resumen.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/offline/offline_screen_loader.dart';
import 'package:matchpay/offline/offline_snapshot_store.dart';
import 'package:matchpay/offline/organizer_home_loader.dart';
import 'package:matchpay/offline/organizer_home_snapshot.dart';

OrganizerHomeData _sampleHomeData() => OrganizerHomeData.empty;

class _FailingSnapshotStore extends OfflineSnapshotStore {
  _FailingSnapshotStore(Directory base)
      : super(userId: 'user-fail', baseDirectory: base);

  @override
  Future<void> save(String key, Map<String, dynamic> payload) async {
    throw StateError('save failed');
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('matchpay_home_loader_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('loadOrganizerHome', () {
    test('fetch exitoso retorna live', () async {
      final result = await loadOrganizerHome(
        snapshotStore: null,
        fetchOverride: () async => _sampleHomeData(),
      );

      expect(result.source, OrganizerHomeLoadSource.live);
      expect(result.data, isNotNull);
    });

    test('fallo de red con snapshot existente usa offlineCache', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      await store.save(organizerHomeSnapshotKey, _sampleHomeData().toJson());

      final result = await loadOrganizerHome(
        snapshotStore: store,
        fetchOverride: () async => throw const SocketException('sin red'),
      );

      expect(result.source, OrganizerHomeLoadSource.offlineCache);
      expect(result.data, isNotNull);
      expect(result.snapshotAt, isNotNull);
    });

    test('fallo de red sin snapshot retorna offlineEmpty', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );

      final result = await loadOrganizerHome(
        snapshotStore: store,
        fetchOverride: () async => throw const SocketException('sin red'),
      );

      expect(result.source, OrganizerHomeLoadSource.offlineEmpty);
      expect(result.data, isNull);
    });

    test('error de parseo online no usa snapshot', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      await store.save(organizerHomeSnapshotKey, _sampleHomeData().toJson());

      final result = await loadOrganizerHome(
        snapshotStore: store,
        fetchOverride: () async {
          throw FormatException('json invalido');
        },
      );

      // Inicio nunca queda en error: degrada a vacío usable.
      expect(result.source, OrganizerHomeLoadSource.live);
      expect(result.data, isNotNull);
      expect(result.data!.resumenes, isEmpty);
    });

    test('fetch que lanza DatosInconsistentes degrada a vacío vivo', () async {
      final result = await loadOrganizerHome(
        snapshotStore: null,
        fetchOverride: () async {
          throw const DatosInconsistentesException('falta snapshot');
        },
      );
      expect(result.source, OrganizerHomeLoadSource.live);
      expect(result.data, OrganizerHomeData.empty);
    });

    test('fallo al guardar snapshot no tumba fetch exitoso', () async {
      final result = await loadOrganizerHome(
        snapshotStore: _FailingSnapshotStore(tempDir),
        fetchOverride: () async => _sampleHomeData(),
      );

      expect(result.source, OrganizerHomeLoadSource.live);
      expect(result.data, isNotNull);
    });
  });

  group('PR2 organizer snapshots', () {
    test('cobros snapshot offline', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      const data = OrganizerCobrosData(resumenes: []);
      await store.save(organizerCobrosSnapshotKey, data.toJson());

      final result = await loadWithOfflineSnapshot(
        snapshotKey: organizerCobrosSnapshotKey,
        snapshotStore: store,
        fetch: () async => throw const SocketException('sin red'),
        encode: (d) => d.toJson(),
        decode: OrganizerCobrosData.fromJson,
      );

      expect(result.source, OfflineScreenLoadSource.offlineCache);
      expect(result.data?.resumenes, isEmpty);
    });

    test('jugadores snapshot offline', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      final data = OrganizerJugadoresData(
        jugadores: [
          Jugador(
            nombre: 'Ana',
            activo: true,
            email: 'ana@test.com',
            createdAt: DateTime(2025, 1, 1),
          ),
        ],
      );
      await store.save(organizerJugadoresSnapshotKey, data.toJson());

      final result = await loadWithOfflineSnapshot(
        snapshotKey: organizerJugadoresSnapshotKey,
        snapshotStore: store,
        fetch: () async => throw const SocketException('sin red'),
        encode: (d) => d.toJson(),
        decode: OrganizerJugadoresData.fromJson,
      );

      expect(result.source, OfflineScreenLoadSource.offlineCache);
      expect(result.data?.jugadores.single.nombre, 'Ana');
    });

    test('historial partidos snapshot offline', () async {
      final store = OfflineSnapshotStore(
        userId: 'user-1',
        baseDirectory: tempDir,
      );
      const data = OrganizerHistorialPartidosData(
        partidos: [],
        convocatorias: [],
      );
      await store.save(organizerHistorialPartidosSnapshotKey, data.toJson());

      final result = await loadWithOfflineSnapshot(
        snapshotKey: organizerHistorialPartidosSnapshotKey,
        snapshotStore: store,
        fetch: () async => throw const SocketException('sin red'),
        encode: (d) => d.toJson(),
        decode: OrganizerHistorialPartidosData.fromJson,
      );

      expect(result.source, OfflineScreenLoadSource.offlineCache);
      expect(result.data?.partidos, isEmpty);
      expect(result.data?.convocatorias, isEmpty);
    });
  });
}
