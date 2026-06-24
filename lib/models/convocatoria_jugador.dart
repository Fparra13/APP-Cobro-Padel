import 'estado_partido.dart';
import 'jugador.dart';
import 'partido.dart';

class ConvocatoriaJugadorEntry {
  final int? id;
  final int partidoId;
  final Jugador jugador;
  final EstadoConfirmacion estado;

  const ConvocatoriaJugadorEntry({
    this.id,
    required this.partidoId,
    required this.jugador,
    required this.estado,
  });

  ConvocatoriaJugadorEntry copyWith({
    int? id,
    int? partidoId,
    Jugador? jugador,
    EstadoConfirmacion? estado,
  }) {
    return ConvocatoriaJugadorEntry(
      id: id ?? this.id,
      partidoId: partidoId ?? this.partidoId,
      jugador: jugador ?? this.jugador,
      estado: estado ?? this.estado,
    );
  }

  factory ConvocatoriaJugadorEntry.fromMap(
    Map<String, dynamic> map,
    Jugador jugador,
  ) {
    return ConvocatoriaJugadorEntry(
      id: map['id'] as int?,
      partidoId: map['partido_id'] as int,
      jugador: jugador,
      estado: EstadoConfirmacion.fromDb(map['estado_confirmacion'] as String?),
    );
  }
}

class ConvocatoriaCompleta {
  final Partido partido;
  final List<ConvocatoriaJugadorEntry> jugadores;

  const ConvocatoriaCompleta({
    required this.partido,
    required this.jugadores,
  });

  int get confirmados =>
      jugadores.where((j) => j.estado == EstadoConfirmacion.confirmado).length;

  int get invitados => jugadores.length;

  int get rechazados =>
      jugadores.where((j) => j.estado == EstadoConfirmacion.rechazado).length;
}
