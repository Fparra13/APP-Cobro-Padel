import '../models/jugador.dart';

/// Filtro simple por nombre para listas largas de jugadores.
List<Jugador> filterJugadoresByName(
  Iterable<Jugador> jugadores,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List<Jugador>.from(jugadores);
  return [
    for (final j in jugadores)
      if (j.nombre.toLowerCase().contains(q)) j,
  ];
}
