import '../core/sport_type.dart';

/// Partido anterior impago que compone la deuda acumulada.
class DeudaPartidoAnterior {
  final int partidoId;
  final DateTime fecha;
  final String? recinto;
  final double montoPendiente;
  final SportType sportType;

  const DeudaPartidoAnterior({
    required this.partidoId,
    required this.fecha,
    this.recinto,
    required this.montoPendiente,
    this.sportType = SportType.padel,
  });
}
