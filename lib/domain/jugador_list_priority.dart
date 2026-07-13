import '../models/jugador.dart';

/// Origen del bloque “arriba” en listas largas de jugadores.
enum JugadorPrioritySource {
  none,
  lastMatch,
  convocatoriaConfirmed,
}

/// Ordena: prioridad → seleccionados → A–Z.
List<Jugador> sortJugadoresByPriority({
  required Iterable<Jugador> jugadores,
  required Set<String> priorityIds,
  Set<String> selectedIds = const {},
}) {
  final list = List<Jugador>.from(jugadores);
  list.sort((a, b) {
    final aPri = priorityIds.contains(a.keyId);
    final bPri = priorityIds.contains(b.keyId);
    if (aPri != bPri) return aPri ? -1 : 1;
    final aSel = selectedIds.contains(a.keyId);
    final bSel = selectedIds.contains(b.keyId);
    if (aSel != bSel) return aSel ? -1 : 1;
    return a.nombre.compareTo(b.nombre);
  });
  return list;
}

/// Parte la lista ya ordenada en bloque prioritario + resto.
({List<Jugador> priority, List<Jugador> rest}) splitJugadoresByPriority({
  required List<Jugador> ordered,
  required Set<String> priorityIds,
}) {
  if (priorityIds.isEmpty) {
    return (priority: const <Jugador>[], rest: ordered);
  }
  final priority = <Jugador>[];
  final rest = <Jugador>[];
  for (final j in ordered) {
    if (priorityIds.contains(j.keyId)) {
      priority.add(j);
    } else {
      rest.add(j);
    }
  }
  return (priority: priority, rest: rest);
}
