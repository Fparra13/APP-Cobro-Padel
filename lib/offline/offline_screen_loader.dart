import 'network_errors.dart';
import 'offline_snapshot_store.dart';

enum OfflineScreenLoadSource { live, offlineCache, offlineEmpty, error }

class OfflineScreenLoadResult<T> {
  final OfflineScreenLoadSource source;
  final T? data;
  final DateTime? snapshotAt;
  final Object? error;

  const OfflineScreenLoadResult({
    required this.source,
    this.data,
    this.snapshotAt,
    this.error,
  });
}

/// Intenta [fetch]; guarda snapshot; fallback solo ante error de red confirmado.
Future<OfflineScreenLoadResult<T>> loadWithOfflineSnapshot<T>({
  required String snapshotKey,
  required OfflineSnapshotStore? snapshotStore,
  required Future<T> Function() fetch,
  required Map<String, dynamic> Function(T data) encode,
  required T Function(Map<String, dynamic> json) decode,
}) async {
  try {
    final data = await fetch();
    // Un fallo al cachear no debe tumbar la pantalla si el fetch ya OK.
    if (snapshotStore != null) {
      try {
        await snapshotStore.save(snapshotKey, encode(data));
      } catch (_) {}
    }
    return OfflineScreenLoadResult(
      source: OfflineScreenLoadSource.live,
      data: data,
    );
  } catch (e) {
    if (!isNetworkError(e)) {
      return OfflineScreenLoadResult(
        source: OfflineScreenLoadSource.error,
        error: e,
      );
    }
    return _loadFromSnapshot(
      snapshotKey: snapshotKey,
      snapshotStore: snapshotStore,
      decode: decode,
    );
  }
}

Future<OfflineScreenLoadResult<T>> _loadFromSnapshot<T>({
  required String snapshotKey,
  required OfflineSnapshotStore? snapshotStore,
  required T Function(Map<String, dynamic> json) decode,
}) async {
  if (snapshotStore == null) {
    return const OfflineScreenLoadResult(
      source: OfflineScreenLoadSource.offlineEmpty,
    );
  }
  final snap = await snapshotStore.read(snapshotKey);
  if (snap == null) {
    return const OfflineScreenLoadResult(
      source: OfflineScreenLoadSource.offlineEmpty,
    );
  }
  try {
    return OfflineScreenLoadResult(
      source: OfflineScreenLoadSource.offlineCache,
      data: decode(snap.payload),
      snapshotAt: snap.fetchedAt,
    );
  } catch (e) {
    return OfflineScreenLoadResult(
      source: OfflineScreenLoadSource.error,
      error: e,
    );
  }
}
