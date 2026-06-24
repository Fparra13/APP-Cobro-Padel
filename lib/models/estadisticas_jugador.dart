class EstadisticasJugador {
  final int jugadorId;
  final String nombre;
  final String? fotoPath;
  final int partidosJugados;
  final int pagosAlDia;
  final int pagosTardios;
  final int partidosImpagos;
  final double promedioDiasPago;
  final double totalGastado;
  final double saldoActual;
  final int convocatoriasConfirmadas;
  final int partidosUltimos90Dias;

  const EstadisticasJugador({
    required this.jugadorId,
    required this.nombre,
    this.fotoPath,
    required this.partidosJugados,
    required this.pagosAlDia,
    required this.pagosTardios,
    required this.partidosImpagos,
    required this.promedioDiasPago,
    required this.totalGastado,
    required this.saldoActual,
    required this.convocatoriasConfirmadas,
    required this.partidosUltimos90Dias,
  });

  double get porcentajePagoAlDia =>
      partidosJugados == 0 ? 0 : (pagosAlDia / partidosJugados) * 100;

  int get scoreBuenPagador =>
      pagosAlDia * 10 - partidosImpagos * 5 - pagosTardios * 2;
}
