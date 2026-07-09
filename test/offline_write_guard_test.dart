import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/connectivity_service.dart';
import 'package:matchpay/offline/offline_exceptions.dart';
import 'package:matchpay/offline/offline_write_guard.dart';

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity(this._online);

  bool _online;

  set online(bool value) => _online = value;

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onlineChanges => const Stream.empty();
}

void main() {
  test('_write offline lanza OfflineWriteBlockedException', () async {
    final guard = OfflineWriteGuard(connectivity: _FakeConnectivity(false));

    expect(
      () => guard.run(() async => 1),
      throwsA(isA<OfflineWriteBlockedException>()),
    );
  });

  test('catch propio dentro del callback se preserva', () async {
    final guard = OfflineWriteGuard(connectivity: _FakeConnectivity(true));

    expect(
      () => guard.run(() async {
        try {
          throw FormatException('parseo roto');
        } on FormatException {
          throw StateError('dominio');
        }
      }),
      throwsA(isA<StateError>()),
    );
  });
}
