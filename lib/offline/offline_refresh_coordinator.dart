import 'dart:async';

import '../core/app_repositories.dart';
import '../core/connectivity_service.dart';

/// Refresca pantallas al recuperar internet vía [AppRepositories.dataRevision].
class OfflineRefreshCoordinator {
  OfflineRefreshCoordinator({ConnectivityService? connectivity})
      : _connectivity = connectivity ?? ConnectivityService.I;

  final ConnectivityService _connectivity;
  StreamSubscription<bool>? _subscription;
  Timer? _notifyDebounce;

  void init() {
    _subscription?.cancel();
    _subscription = _connectivity.onlineChanges
        .where((online) => online)
        .listen((_) => _scheduleRefresh());
  }

  void dispose() {
    _subscription?.cancel();
    _notifyDebounce?.cancel();
  }

  void _scheduleRefresh() {
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 450), () {
      AppRepositories.notifyDataChanged();
    });
  }
}
