import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/estado_partido_publico.dart';
import 'package:matchpay/models/convocatoria_jugador.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/models/mi_convocatoria.dart';
import 'package:matchpay/models/partido.dart';

Partido _partido({
  required DateTime fecha,
  EstadoPartido estado = EstadoPartido.organizando,
  int cuposMax = 4,
  DateTime? reprogramadoEn,
}) =>
    Partido(
      fecha: fecha,
      estado: estado,
      cuposMax: cuposMax,
      createdAt: fecha,
      reprogramadoEn: reprogramadoEn,
    );

ConvocatoriaJugadorEntry _titular({
  required int partidoId,
  EstadoConfirmacion estado = EstadoConfirmacion.invitado,
  DateTime? tiempoLimite,
}) =>
    ConvocatoriaJugadorEntry(
      partidoId: partidoId,
      jugador: Jugador(nombre: 'Ana', createdAt: DateTime(2026)),
      estado: estado,
      tiempoLimite: tiempoLimite,
    );

ConvocatoriaCompleta _conv({
  required Partido partido,
  List<ConvocatoriaJugadorEntry>? jugadores,
}) =>
    ConvocatoriaCompleta(
      partido: partido,
      jugadores: jugadores ??
          [
            _titular(partidoId: partido.id ?? 1, estado: EstadoConfirmacion.confirmado),
            _titular(partidoId: partido.id ?? 1, estado: EstadoConfirmacion.confirmado),
            _titular(partidoId: partido.id ?? 1, estado: EstadoConfirmacion.confirmado),
            _titular(partidoId: partido.id ?? 1, estado: EstadoConfirmacion.confirmado),
          ],
    );

void main() {
  final ref = DateTime(2026, 7, 8, 12);

  test('partido completo futuro → confirmado', () {
    final conv = _conv(partido: _partido(fecha: DateTime(2026, 7, 10, 20)));
    final view = PartidoEstadoPublicoView.resolve(conv, ref);
    expect(view.estado, EstadoPartidoPublico.confirmado);
  });

  test('faltan jugadores con tiempo → esperando confirmaciones', () {
    final partido = _partido(fecha: DateTime(2026, 7, 12, 20));
    final conv = _conv(
      partido: partido,
      jugadores: [
        _titular(partidoId: 1, estado: EstadoConfirmacion.confirmado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.invitado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.invitado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.rechazado),
      ],
    );
    final view = PartidoEstadoPublicoView.resolve(conv, ref);
    expect(view.estado, EstadoPartidoPublico.esperandoConfirmaciones);
    expect(view.faltan, 3);
  });

  test('faltan jugadores y queda poco tiempo → en evaluación', () {
    final limite = DateTime(2026, 7, 8, 16);
    final partido = _partido(fecha: DateTime(2026, 7, 8, 17));
    final conv = _conv(
      partido: partido,
      jugadores: [
        _titular(
          partidoId: 1,
          estado: EstadoConfirmacion.confirmado,
          tiempoLimite: limite,
        ),
        _titular(
          partidoId: 1,
          estado: EstadoConfirmacion.confirmado,
          tiempoLimite: limite,
        ),
        _titular(
          partidoId: 1,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
        _titular(
          partidoId: 1,
          estado: EstadoConfirmacion.rechazado,
          tiempoLimite: limite,
        ),
      ],
    );
    final view = PartidoEstadoPublicoView.resolve(conv, ref);
    expect(view.estado, EstadoPartidoPublico.enEvaluacion);
  });

  test('sin convocatoria enviada no pasa a en evaluación aunque quede poco', () {
    final partido = _partido(fecha: DateTime(2026, 7, 8, 17));
    final conv = _conv(
      partido: partido,
      jugadores: [
        _titular(partidoId: 1, estado: EstadoConfirmacion.confirmado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.confirmado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.invitado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.rechazado),
      ],
    );
    final view = PartidoEstadoPublicoView.resolve(conv, ref);
    expect(view.estado, EstadoPartidoPublico.esperandoConfirmaciones);
  });

  test('cupo imposible marca en evaluación con flag', () {
    final limite = DateTime(2026, 7, 9, 12);
    final partido = _partido(fecha: DateTime(2026, 7, 12, 20), cuposMax: 10);
    final conv = _conv(
      partido: partido,
      jugadores: [
        for (var i = 0; i < 7; i++)
          _titular(
            partidoId: 1,
            estado: EstadoConfirmacion.confirmado,
            tiempoLimite: limite,
          ),
        _titular(
          partidoId: 1,
          estado: EstadoConfirmacion.invitado,
          tiempoLimite: limite,
        ),
      ],
    );
    final view = PartidoEstadoPublicoView.resolve(conv, ref);
    expect(view.estado, EstadoPartidoPublico.enEvaluacion);
    expect(view.cupoImposible, isTrue);
  });

  test('reprogramado reciente con cupos libres → reprogramado', () {
    final conv = _conv(
      partido: _partido(
        fecha: DateTime(2026, 7, 12, 20),
        reprogramadoEn: DateTime(2026, 7, 8, 10),
      ),
      jugadores: [
        _titular(partidoId: 1, estado: EstadoConfirmacion.confirmado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.invitado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.invitado),
        _titular(partidoId: 1, estado: EstadoConfirmacion.invitado),
      ],
    );
    final view = PartidoEstadoPublicoView.resolve(conv, ref);
    expect(view.estado, EstadoPartidoPublico.reprogramado);
  });

  test('jugador con convocatoria reprogramada pendiente → reprogramado', () {
    final partido = _partido(
      fecha: DateTime(2026, 7, 12, 20),
      reprogramadoEn: DateTime(2026, 7, 8, 10),
    );
    final conv = MiConvocatoria(
      partido: partido,
      entry: _titular(
        partidoId: 1,
        estado: EstadoConfirmacion.invitado,
      ),
    );
    final view = PartidoEstadoPublicoView.resolveJugador(conv, null, ref);
    expect(view?.estado, EstadoPartidoPublico.reprogramado);
  });
}
