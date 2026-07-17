import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/jugador_list_priority.dart';
import 'package:matchpay/models/jugador.dart';

void main() {
  Jugador j(String nombre, {int id = 1}) => Jugador(
        id: id,
        nombre: nombre,
        createdAt: DateTime(2024),
      );

  test('prioridad y selección mandan sobre A-Z', () {
    final a = j('Ana', id: 1);
    final b = j('Bruno', id: 2);
    final c = j('Carla', id: 3);
    final sorted = sortJugadoresByPriority(
      jugadores: [a, b, c],
      priorityIds: {b.keyId},
      selectedIds: {a.keyId},
    );
    // Bruno (prioridad) → Ana (seleccionada) → Carla
    expect(sorted.map((x) => x.nombre), ['Bruno', 'Ana', 'Carla']);
  });

  test('split separa bloque prioritario', () {
    final a = j('Ana', id: 1);
    final b = j('Bruno', id: 2);
    final ordered = sortJugadoresByPriority(
      jugadores: [a, b],
      priorityIds: {b.keyId},
    );
    final parts = splitJugadoresByPriority(
      ordered: ordered,
      priorityIds: {b.keyId},
    );
    expect(parts.priority.single.nombre, 'Bruno');
    expect(parts.rest.single.nombre, 'Ana');
  });

  test('convocatoria: invitados, luego espera, luego resto A-Z', () {
    final ana = j('Ana', id: 1);
    final bruno = j('Bruno', id: 2);
    final carla = j('Carla', id: 3);
    final diego = j('Diego', id: 4);
    final sorted = sortJugadoresParaConvocatoria(
      jugadores: [ana, bruno, carla, diego],
      invitadosIds: [bruno.keyId, ana.keyId],
      esperaIds: [diego.keyId],
      priorityIds: {carla.keyId},
    );
    expect(
      sorted.map((x) => x.nombre),
      ['Bruno', 'Ana', 'Diego', 'Carla'],
    );
  });
}
