import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/offline/offline_snapshot_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('matchpay_offline_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save and read snapshot round-trip', () async {
    final store = OfflineSnapshotStore(
      userId: 'user-1',
      baseDirectory: tempDir,
    );

    await store.save('organizer_home', {'hello': 'world'});
    final snap = await store.read('organizer_home');

    expect(snap, isNotNull);
    expect(snap!.payload['hello'], 'world');
    expect(snap.fetchedAt.isBefore(DateTime.now().add(const Duration(seconds: 1))),
        isTrue);
  });

  test('read with schemaVersion distinta retorna null', () async {
    final store = OfflineSnapshotStore(
      userId: 'user-1',
      baseDirectory: tempDir,
    );
    final file = File('${tempDir.path}/user-1/bad.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '{"schemaVersion":999,"fetchedAt":"2026-01-01T00:00:00.000Z","payload":{}}',
    );

    final snap = await store.read('bad');
    expect(snap, isNull);
  });
}
