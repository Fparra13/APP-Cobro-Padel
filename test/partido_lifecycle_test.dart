import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/partido_lifecycle.dart';
import 'package:matchpay/models/convocatoria_jugador.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/models/mi_convocatoria.dart';
import 'package:matchpay/models/partido.dart';

Partido _partido({
  required DateTime fecha,
  EstadoPartido estado = EstadoPartido.organizando,
}) =>
    Partido(fecha: fecha, estado: estado, createdAt: fecha);

ConvocatoriaJugadorEntry _entry({
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

MiConvocatoria _miConvocatoria({
  required Partido partido,
  EstadoConfirmacion estado = EstadoConfirmacion.invitado,
  DateTime? tiempoLimite,
}) =>
    MiConvocatoria(
      entry: _entry(
        partidoId: partido.id ?? 1,
        estado: estado,
        tiempoLimite: tiempoLimite,
      ),
      partido: partido,
    );

ConvocatoriaCompleta _convocatoria({
  required Partido partido,
  int confirmados = 0,
}) {
  final jugadores = <ConvocatoriaJugadorEntry>[
  for (var i = 0; i < confirmados; i++)
    _entry(
      partidoId: partido.id ?? 1,
      estado: EstadoConfirmacion.confirmado,
    ),
  ];
  return ConvocatoriaCompleta(partido: partido, jugadores: jugadores);
}

void main() {
  final ref = DateTime(2026, 7, 8, 12);

  test('convocatoria expirada cuando pasó la hora del partido', () {
    final ref = DateTime(2026, 7, 8, 12);

    expect(
      PartidoLifecycle.convocatoriaExpirada(
        _partido(fecha: DateTime(2026, 7, 10, 20)),
        ref,
      ),
      isFalse,
    );
    expect(
      PartidoLifecycle.convocatoriaExpirada(
        _partido(fecha: DateTime(2026, 7, 7, 8)),
        ref,
      ),
      isTrue,
    );
    expect(
      PartidoLifecycle.convocatoriaExpirada(
        _partido(fecha: DateTime(2026, 7, 8, 10)),
        ref,
      ),
      isTrue,
    );
    expect(
      PartidoLifecycle.convocatoriaExpirada(
        _partido(fecha: DateTime(2026, 7, 8, 12)),
        ref,
      ),
      isTrue,
    );
  });

  test('jugador no puede responder si la convocatoria expiró', () {
    final pasado = _partido(fecha: DateTime(2026, 7, 7, 8));
    final conv = _miConvocatoria(partido: pasado);

    expect(PartidoLifecycle.puedeResponderJugador(conv, ref), isFalse);
  });

  test('jugador no puede responder si venció el plazo individual', () {
    final futuro = _partido(fecha: DateTime(2026, 7, 10, 20));
    final conv = _miConvocatoria(
      partido: futuro,
      tiempoLimite: DateTime(2026, 7, 7, 18),
    );

    expect(PartidoLifecycle.puedeResponderJugador(conv, ref), isFalse);
  });

  test('jugador sí puede responder antes de expirar convocatoria y plazo', () {
    final futuro = _partido(fecha: DateTime(2026, 7, 10, 20));
    final conv = _miConvocatoria(
      partido: futuro,
      tiempoLimite: DateTime(2026, 7, 9, 18),
    );

    expect(PartidoLifecycle.puedeResponderJugador(conv, ref), isTrue);
  });

  test('organizando con fecha pasada no asume partido jugado', () {
    final pasado = _partido(
      fecha: DateTime(2026, 7, 7, 8),
      estado: EstadoPartido.organizando,
    );
    final conv = _convocatoria(partido: pasado, confirmados: 2);

    expect(PartidoLifecycle.evidenciaPartidoJugado(conv, ref), isFalse);
    expect(
      PartidoLifecycle.situacionOrganizador(conv, ref),
      ConvocatoriaOrganizadorSituacion.sinResolver,
    );
    expect(PartidoLifecycle.puedeRegistrarGastos(conv, ref), isFalse);
  });

  test('confirmado con fecha pasada sí permite registrar gastos', () {
    final pasado = _partido(
      fecha: DateTime(2026, 7, 7, 8),
      estado: EstadoPartido.confirmado,
    );
    final conv = _convocatoria(partido: pasado, confirmados: 4);

    expect(PartidoLifecycle.evidenciaPartidoJugado(conv, ref), isTrue);
    expect(
      PartidoLifecycle.situacionOrganizador(conv, ref),
      ConvocatoriaOrganizadorSituacion.listoParaGastos,
    );
    expect(PartidoLifecycle.puedeRegistrarGastos(conv, ref), isTrue);
  });

  test('partido cancelado no es convocatoria activa', () {
    final cancelado = _partido(
      fecha: DateTime(2026, 7, 10, 20),
      estado: EstadoPartido.cancelado,
    );

    expect(PartidoLifecycle.convocatoriaActiva(cancelado), isFalse);
    expect(PartidoLifecycle.convocatoriaExpirada(cancelado, ref), isFalse);
  });
}
