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
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });
  return list;
}

/// Orden para armar convocatoria:
/// 1) invitados (orden de selección),
/// 2) lista de espera (orden de prioridad),
/// 3) resto: prioridad del último partido → A–Z.
List<Jugador> sortJugadoresParaConvocatoria({
  required Iterable<Jugador> jugadores,
  required List<String> invitadosIds,
  required List<String> esperaIds,
  Set<String> priorityIds = const {},
}) {
  final byId = <String, Jugador>{
    for (final j in jugadores)
      if (j.keyId.isNotEmpty) j.keyId: j,
  };
  final result = <Jugador>[];
  final seen = <String>{};

  void appendOrdered(List<String> ids) {
    for (final id in ids) {
      if (seen.contains(id)) continue;
      final j = byId[id];
      if (j == null) continue;
      result.add(j);
      seen.add(id);
    }
  }

  appendOrdered(invitadosIds);
  appendOrdered(esperaIds);

  final rest = byId.values.where((j) => !seen.contains(j.keyId)).toList()
    ..sort((a, b) {
      final aPri = priorityIds.contains(a.keyId);
      final bPri = priorityIds.contains(b.keyId);
      if (aPri != bPri) return aPri ? -1 : 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
  result.addAll(rest);
  return result;
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
