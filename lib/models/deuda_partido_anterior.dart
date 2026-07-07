import '../core/sport_type.dart';

/// Partido anterior impago que compone la deuda acumulada.
class DeudaPartidoAnterior {
  final int partidoId;
  final DateTime fecha;
  final String? recinto;
  /// Pendiente neto del partido (snapshot + cargo − pagado en partido).
  final double pendienteNeto;
  final SportType sportType;

  const DeudaPartidoAnterior({
    required this.partidoId,
    required this.fecha,
    this.recinto,
    required this.pendienteNeto,
    this.sportType = SportType.padel,
  });
}
