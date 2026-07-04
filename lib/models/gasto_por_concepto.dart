/// Gasto acumulado del jugador en un concepto (su parte en partidos jugados).
class GastoPorConcepto {
  final String concepto;
  final double monto;

  const GastoPorConcepto({
    required this.concepto,
    required this.monto,
  });
}

/// Periodo para reportes personales del jugador.
enum PeriodoResumenJugador {
  mes,
  anio,
  todo,
}
