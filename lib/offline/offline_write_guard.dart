import '../core/connectivity_service.dart';
import 'offline_exceptions.dart';

/// Bloquea escrituras remotas sin conexión (modo solo lectura).
///
/// Usar vía [SupabaseHelpers.write] en repositorios cloud. SQLite local
/// no pasa por este guard (sigue usable offline).
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
