import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'supabase_config.dart';

/// Servicio de conectividad con caché corta (5 s) y confirmación de internet real.
abstract class ConnectivityService {
  static ConnectivityService I = ConnectivityServiceImpl();

  Stream<bool> get onlineChanges;

  Future<bool> get isOnline;
}

class ConnectivityServiceImpl implements ConnectivityService {
  ConnectivityServiceImpl({
    Connectivity? connectivity,
    Duration cacheTtl = const Duration(seconds: 5),
    Duration lookupTimeout = const Duration(seconds: 3),
  })  : _connectivity = connectivity ?? Connectivity(),
        _cacheTtl = cacheTtl,
        _lookupTimeout = lookupTimeout {
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_refreshConfirmedOnline(emitChanges: true));
    });
    unawaited(_refreshConfirmedOnline(emitChanges: false));
  }

  final Connectivity _connectivity;
  final Duration _cacheTtl;
  final Duration _lookupTimeout;
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool? _cachedOnline;
  DateTime? _cachedAt;
  bool? _lastEmitted;

  @override
  Stream<bool> get onlineChanges => _onlineController.stream;

  @override
  Future<bool> get isOnline async {
    final now = DateTime.now();
    if (_cachedOnline != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return _cachedOnline!;
    }
    return _refreshConfirmedOnline(emitChanges: false);
  }

  Future<bool> _refreshConfirmedOnline({required bool emitChanges}) async {
    final hasTransport = await _hasNetworkTransport();
    final confirmed = hasTransport && await _hasInternetAccess();
    _cachedOnline = confirmed;
    _cachedAt = DateTime.now();

    if (emitChanges && _lastEmitted != confirmed) {
      _lastEmitted = confirmed;
      _onlineController.add(confirmed);
    } else {
      _lastEmitted ??= confirmed;
    }
    return confirmed;
  }

  Future<bool> _hasNetworkTransport() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty) return false;
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasInternetAccess() async {
    // Varios hosts: el DNS de Supabase a veces falla en móvil/VPN aunque hay internet.
    final hosts = <String>{
      _lookupHost(),
      'one.one.one.one',
      'dns.google',
    };
    for (final host in hosts) {
      try {
        final result = await InternetAddress.lookup(host).timeout(
          _lookupTimeout,
          onTimeout: () => <InternetAddress>[],
        );
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  String _lookupHost() {
    final url = SupabaseConfig.supabaseUrl;
    if (url.isEmpty) return 'one.one.one.one';
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'one.one.one.one';
    }
  }

  @visibleForTesting
  void dispose() {
    _subscription?.cancel();
    _onlineController.close();
  }
}
