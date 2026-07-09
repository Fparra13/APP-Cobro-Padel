import 'package:flutter/foundation.dart';

enum OfflineDisplayMode { live, offlineCached, offlineEmpty }

/// Estado global para banner offline y bloqueo de acciones de escritura.
class OfflineStatusController extends ChangeNotifier {
  OfflineDisplayMode _mode = OfflineDisplayMode.live;
  DateTime? _activeSnapshotAt;

  OfflineDisplayMode get mode => _mode;

  DateTime? get activeSnapshotAt => _activeSnapshotAt;

  bool get isReadOnly => _mode != OfflineDisplayMode.live;

  void markLive() {
    if (_mode == OfflineDisplayMode.live && _activeSnapshotAt == null) return;
    _mode = OfflineDisplayMode.live;
    _activeSnapshotAt = null;
    notifyListeners();
  }

  void markOfflineCached(DateTime fetchedAt) {
    _mode = OfflineDisplayMode.offlineCached;
    _activeSnapshotAt = fetchedAt;
    notifyListeners();
  }

  void markOfflineEmpty() {
    _mode = OfflineDisplayMode.offlineEmpty;
    _activeSnapshotAt = null;
    notifyListeners();
  }
}
