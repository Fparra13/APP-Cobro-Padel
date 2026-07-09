import '../services/calculation_service.dart';

/// Reparto de gastos compartidos entre asistentes al partido.
class GastoCompartidoLogic {
  GastoCompartidoLogic._();

  /// Participantes que pagan el gasto.
  ///
  /// Con [repartoEntreTodos] activo (valor por defecto) divide entre todos los
  /// asistentes aunque cambie la lista de jugadores seleccionados.
  static Set<String> participantesReparto({
    required Set<String> participantesExplicitos,
    required Set<String> asistentes,
    required bool repartoEntreTodos,
    required bool sinParticipantesExplicito,
    required double monto,
  }) {
    if (monto <= 0 || asistentes.isEmpty) return {};
    if (sinParticipantesExplicito) return {};
    if (repartoEntreTodos) return Set<String>.from(asistentes);
    return participantesExplicitos.where(asistentes.contains).toSet();
  }

  static double cuotaJugador({
    required double montoTotal,
    required Set<String> participantes,
    required String jugadorId,
  }) {
    if (!participantes.contains(jugadorId) || participantes.isEmpty) {
      return 0;
    }
    return CalculationService.prorratear(montoTotal, participantes.length);
  }
}
