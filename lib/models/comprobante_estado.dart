/// Estado explícito del comprobante de pago del jugador.
enum ComprobanteEstado {
  enRevision,
  aprobado,
  rechazado;

  static const dbEnRevision = 'en_revision';
  static const dbAprobado = 'aprobado';
  static const dbRechazado = 'rechazado';

  String get dbValue => switch (this) {
        ComprobanteEstado.enRevision => dbEnRevision,
        ComprobanteEstado.aprobado => dbAprobado,
        ComprobanteEstado.rechazado => dbRechazado,
      };

  static ComprobanteEstado? fromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case dbEnRevision:
        return ComprobanteEstado.enRevision;
      case dbAprobado:
        return ComprobanteEstado.aprobado;
      case dbRechazado:
        return ComprobanteEstado.rechazado;
      default:
        return null;
    }
  }

  /// Inferencia legacy cuando la columna aún no venía en el row.
  static ComprobanteEstado? fromLegacy({
    required bool? comprobanteValidado,
    required String? comprobanteUrl,
    required double? montoPagoDeclarado,
  }) {
    if (comprobanteValidado == true) return ComprobanteEstado.aprobado;
    final url = comprobanteUrl?.trim() ?? '';
    final declarado = montoPagoDeclarado ?? 0;
    if (url.isNotEmpty || declarado > 0.005) {
      return ComprobanteEstado.enRevision;
    }
    return null;
  }
}
