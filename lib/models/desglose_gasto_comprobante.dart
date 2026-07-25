/// Gasto variable del desglose jugador con comprobante opcional.
class DesgloseGastoComprobante {
  final String concepto;
  final double monto;
  final String? comprobanteUrl;

  const DesgloseGastoComprobante({
    required this.concepto,
    required this.monto,
    this.comprobanteUrl,
  });

  bool get tieneComprobante {
    final u = comprobanteUrl?.trim();
    return u != null && u.isNotEmpty;
  }
}
