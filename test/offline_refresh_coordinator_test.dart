import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/app_repositories.dart';
import 'package:matchpay/core/connectivity_service.dart';
import 'package:matchpay/offline/offline_refresh_coordinator.dart';

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity(this._controller);

  final StreamController<bool> _controller;

  @override
  Stream<bool> get onlineChanges => _controller.stream;

  @override
  Future<bool> get isOnline async => true;
}

void main() {
  test('reconexión dispara notifyDataChanged una sola vez (debounced)', () async {
    final controller = StreamController<bool>.broadcast();
    final connectivity = _FakeConnectivity(controller);
    final coordinator = OfflineRefreshCoordinator(connectivity: connectivity);

    var notifyCount = 0;
    void listener() => notifyCount++;
    AppRepositories.dataRevision.addListener(listener);

    coordinator.init();
    controller.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(notifyCount, 1);

    coordinator.dispose();
    AppRepositories.dataRevision.removeListener(listener);
    await controller.close();
  });
}
