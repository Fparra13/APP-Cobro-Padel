import 'package:flutter/foundation.dart';

/// Evita ejecutar la misma acción async más de una vez a la vez.
class SingleActionGuard {
  SingleActionGuard._();
  static final SingleActionGuard instance = SingleActionGuard._();

  final Set<Object> _locks = {};

  bool isLocked(Object key) => _locks.contains(key);

  Future<T?> run<T>(Object key, Future<T?> Function() action) async {
    if (_locks.contains(key)) return null;
    _locks.add(key);
    try {
      return await action();
    } catch (e, st) {
      debugPrint('SingleActionGuard($key): $e\n$st');
      rethrow;
    } finally {
      _locks.remove(key);
    }
  }
}

Future<T?> runOnce<T>(Object key, Future<T?> Function() action) =>
    SingleActionGuard.instance.run(key, action);
