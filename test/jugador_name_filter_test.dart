import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/utils/jugador_name_filter.dart';

void main() {
  Jugador j(String nombre) => Jugador(
        nombre: nombre,
        createdAt: DateTime(2024),
      );

  test('filtra por substring case-insensitive', () {
    final lista = [j('Francisco'), j('Ana'), j('fran garcia')];
    final r = filterJugadoresByName(lista, 'Fran');
    expect(r.map((x) => x.nombre), ['Francisco', 'fran garcia']);
  });

  test('query vacía devuelve todos', () {
    final lista = [j('A'), j('B')];
    expect(filterJugadoresByName(lista, '  '), hasLength(2));
  });
}
