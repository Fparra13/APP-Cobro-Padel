/// Escritura bloqueada porque no hay conexión (modo solo lectura).
class OfflineWriteBlockedException implements Exception {
  const OfflineWriteBlockedException();

  @override
  String toString() => 'OfflineWriteBlockedException';
}

/// No hay snapshot local para la clave solicitada.
class OfflineCacheMissException implements Exception {
  const OfflineCacheMissException();

  @override
  String toString() => 'OfflineCacheMissException';
}
