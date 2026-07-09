import 'dart:async';
import 'dart:io';

import 'offline_exceptions.dart';

export 'offline_exceptions.dart';

/// Indica si [error] es probablemente un fallo de red/conectividad (no un bug de app).
bool isNetworkError(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is IOException) return true;
  if (error is HandshakeException) return true;
  if (error is OfflineWriteBlockedException) return true;

  final message = error.toString().toLowerCase();
  const networkHints = [
    'clientexception',
    'socketfailed',
    'failed host lookup',
    'network is unreachable',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection timed out',
    'tiempo de espera agotado',
    'no address associated with hostname',
    'software caused connection abort',
    'unable to resolve host',
  ];
  for (final hint in networkHints) {
    if (message.contains(hint)) return true;
  }
  return false;
}
