import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/convocatoria_cupo_logic.dart';
import 'package:matchpay/models/convocatoria_jugador.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/models/partido.dart';

Partido _partido({
  required DateTime fecha,
  int cuposMax = 10,
}) =>
    Partido(
      id: 1,
      fecha: fecha,
      estado: EstadoPartido.organizando,
      cuposMax: cuposMax,
      createdAt: fecha,
    );

ConvocatoriaJugadorEntry _entry({
  required int partidoId,
  EstadoConfirmacion estado = EstadoConfirmacion.invitado,
  bool esSuplente = false,
  DateTime? tiempoLimite,
}) =>
    ConvocatoriaJugadorEntry(
      partidoId: partidoId,
      jugador: Jugador(nombre: 'Jugador', createdAt: DateTime(2026)),
      estado: estado,
      esSuplente: esSuplente,
      tiempoLimite: tiempoLimite,
    );

ConvocatoriaCompleta _conv({
  required Partido partido,
  required List<ConvocatoriaJugadorEntry> jugadores,
}) =>
    ConvocatoriaCompleta(partido: partido, jugadores: jugadores);

void main() {
  final ref = DateTime(2026, 7, 8, 12);
  final limite = DateTime(2026, 7, 9, 12);
  final futuro = DateTime(2026, 7, 12, 20);

  test('maxConfirmadosPosible suma confirmados, pendientes y suplentes', () {
    final conv = _conv(
      partido: _partido(fecha: futuro, cuposMax: 10),
      jugadores: [
        for (var i = 0; i < 7; i++)
          _entry(
            partidoId: 1,
            estado: EstadoConfirmacion.confirmado,
            tiempoLimite: limite,
          ),
        _entry(
          partidoId: 1,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
        _entry(
          partidoId: 1,
          esSuplente: true,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
      ],
    );

    expect(ConvocatoriaCupoLogic.maxConfirmadosPosible(conv), 9);
  });

  test('cupo imposible cuando max posible < cupos', () {
    final conv = _conv(
      partido: _partido(fecha: futuro, cuposMax: 10),
      jugadores: [
        for (var i = 0; i < 7; i++)
          _entry(
            partidoId: 1,
            estado: EstadoConfirmacion.confirmado,
            tiempoLimite: limite,
          ),
        _entry(
          partidoId: 1,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
        _entry(
          partidoId: 1,
          esSuplente: true,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
      ],
    );

    expect(ConvocatoriaCupoLogic.cupoImposible(conv, ref), isTrue);
  });

  test('cupo posible si aún alcanzan con pendientes y suplentes', () {
    final conv = _conv(
      partido: _partido(fecha: futuro, cuposMax: 10),
      jugadores: [
        for (var i = 0; i < 7; i++)
          _entry(
            partidoId: 1,
            estado: EstadoConfirmacion.confirmado,
            tiempoLimite: limite,
          ),
        for (var i = 0; i < 2; i++)
          _entry(
            partidoId: 1,
            estado: EstadoConfirmacion.invitado,
            tiempoLimite: limite,
          ),
        _entry(
          partidoId: 1,
          esSuplente: true,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
      ],
    );

    expect(ConvocatoriaCupoLogic.cupoImposible(conv, ref), isFalse);
  });

  test('no cupo imposible sin convocatoria enviada', () {
    final conv = _conv(
      partido: _partido(fecha: futuro, cuposMax: 10),
      jugadores: [
        _entry(partidoId: 1, estado: EstadoConfirmacion.confirmado),
        _entry(partidoId: 1, estado: EstadoConfirmacion.invitado),
      ],
    );

    expect(ConvocatoriaCupoLogic.cupoImposible(conv, ref), isFalse);
  });

  test('lista de espera solo visible con cupos completos o gente en espera', () {
    expect(
      ConvocatoriaCupoLogic.mostrarListaEspera(
        seleccionados: 3,
        cuposMax: 4,
        enEspera: 0,
      ),
      isFalse,
    );
    expect(
      ConvocatoriaCupoLogic.mostrarListaEspera(
        seleccionados: 4,
        cuposMax: 4,
        enEspera: 0,
      ),
      isTrue,
    );
    expect(
      ConvocatoriaCupoLogic.mostrarListaEspera(
        seleccionados: 2,
        cuposMax: 4,
        enEspera: 1,
      ),
      isTrue,
    );
  });

  test('marcar de más con cupos llenos va a lista de espera', () {
    expect(
      ConvocatoriaCupoLogic.destinoSeleccionBorrador(
        invitadosActuales: 3,
        cuposMax: 4,
      ),
      'invitado',
    );
    expect(
      ConvocatoriaCupoLogic.destinoSeleccionBorrador(
        invitadosActuales: 4,
        cuposMax: 4,
      ),
      'espera',
    );
  });

  group('aplicarToggleSeleccionBorrador', () {
    SeleccionBorradorCupo sel(
      List<String> titulares,
      List<String> reservas, {
      required String id,
      required bool seleccionar,
      int cuposMax = 6,
    }) =>
        ConvocatoriaCupoLogic.aplicarToggleSeleccionBorrador(
          titulares: titulares,
          reservas: reservas,
          cuposMax: cuposMax,
          jugadorId: id,
          seleccionar: seleccionar,
        );

    SeleccionBorradorCupo selectMany(List<String> ids, {int cuposMax = 6}) {
      var state = const SeleccionBorradorCupo(titulares: [], reservas: []);
      for (final id in ids) {
        state = sel(
          state.titulares,
          state.reservas,
          id: id,
          seleccionar: true,
          cuposMax: cuposMax,
        );
      }
      return state;
    }

    test('caso 1: cupo 6 con 9 seleccionados → 6 titulares + 3 reservas', () {
      final state = selectMany(['1', '2', '3', '4', '5', '6', '7', '8', '9']);
      expect(state.titulares, ['1', '2', '3', '4', '5', '6']);
      expect(state.reservas, ['7', '8', '9']);
    });

    test(
      'caso 2: desmarcar un titular promueve la primera reserva',
      () {
        final start = selectMany(['1', '2', '3', '4', '5', '6', '7', '8', '9']);
        final next = sel(
          start.titulares,
          start.reservas,
          id: '3',
          seleccionar: false,
        );
        expect(next.titulares, ['1', '2', '4', '5', '6', '7']);
        expect(next.reservas, ['8', '9']);
      },
    );

    test(
      'caso 3: desmarcar dos titulares promueve las dos primeras reservas',
      () {
        var state = selectMany(['1', '2', '3', '4', '5', '6', '7', '8', '9']);
        state = sel(
          state.titulares,
          state.reservas,
          id: '2',
          seleccionar: false,
        );
        state = sel(
          state.titulares,
          state.reservas,
          id: '5',
          seleccionar: false,
        );
        expect(state.titulares, ['1', '3', '4', '6', '7', '8']);
        expect(state.reservas, ['9']);
      },
    );

    test(
      'caso 4: desmarcar una reserva no altera titulares',
      () {
        final start = selectMany(['1', '2', '3', '4', '5', '6', '7', '8', '9']);
        final next = sel(
          start.titulares,
          start.reservas,
          id: '8',
          seleccionar: false,
        );
        expect(next.titulares, ['1', '2', '3', '4', '5', '6']);
        expect(next.reservas, ['7', '9']);
      },
    );

    test(
      'caso 5: con cupo libre, el nuevo seleccionado entra como titular',
      () {
        final start = selectMany(['1', '2', '3', '4', '5']);
        final next = sel(
          start.titulares,
          start.reservas,
          id: '10',
          seleccionar: true,
        );
        expect(next.titulares, ['1', '2', '3', '4', '5', '10']);
        expect(next.reservas, isEmpty);
      },
    );

    test(
      'caso 6: liberar cupo y elegir otro mantiene clasificación coherente',
      () {
        var state = selectMany(['1', '2', '3', '4', '5', '6', '7', '8', '9']);
        // Liberar un titular → promueve 7; quedan reservas 8,9.
        state = sel(
          state.titulares,
          state.reservas,
          id: '1',
          seleccionar: false,
        );
        expect(state.titulares, ['2', '3', '4', '5', '6', '7']);
        expect(state.reservas, ['8', '9']);
        // Cupo lleno: nuevo jugador va al final de reservas.
        state = sel(
          state.titulares,
          state.reservas,
          id: '10',
          seleccionar: true,
        );
        expect(state.titulares, ['2', '3', '4', '5', '6', '7']);
        expect(state.reservas, ['8', '9', '10']);
      },
    );
  });
}
