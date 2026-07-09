import '../core/connectivity_service.dart';
import 'offline_exceptions.dart';

/// Punto único de entrada para escrituras (pendiente de envolver AppRepositories).
class OfflineWriteGuard {
  OfflineWriteGuard({ConnectivityService? connectivity})
      : _connectivity = connectivity ?? ConnectivityService.I;

  final ConnectivityService _connectivity;

  Future<T> run<T>(Future<T> Function() action) async {
    if (!await _connectivity.isOnline) {
      throw const OfflineWriteBlockedException();
    }
    return action();
  }
}
