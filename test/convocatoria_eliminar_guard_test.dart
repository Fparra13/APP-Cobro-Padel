import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/convocatoria_jugador.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/models/partido.dart';
import 'package:matchpay/utils/convocatoria_organizador_actions.dart';

ConvocatoriaJugadorEntry _entry({
  required EstadoConfirmacion estado,
  bool suplente = false,
}) {
  return ConvocatoriaJugadorEntry(
    partidoId: 1,
    jugador: Jugador(
      supabaseId: 'j-${estado.name}',
      nombre: estado.name,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    estado: estado,
    esSuplente: suplente,
  );
}

ConvocatoriaCompleta _conv(List<ConvocatoriaJugadorEntry> jugadores) {
  return ConvocatoriaCompleta(
    partido: Partido(
      id: 1,
      fecha: DateTime.utc(2026, 7, 20, 20),
      createdAt: DateTime.utc(2026, 7, 15),
      estado: EstadoPartido.organizando,
    ),
    jugadores: jugadores,
  );
}

void main() {
  test('sin confirmaciones permite eliminar', () {
    expect(debeForzarCancelarEnVezDeEliminar(null), isFalse);
    expect(
      debeForzarCancelarEnVezDeEliminar(
        _conv([
          _entry(estado: EstadoConfirmacion.invitado),
          _entry(estado: EstadoConfirmacion.rechazado),
        ]),
      ),
      isFalse,
    );
  });

  test('con al menos un confirmado fuerza cancelar', () {
    expect(
      debeForzarCancelarEnVezDeEliminar(
        _conv([
          _entry(estado: EstadoConfirmacion.confirmado),
          _entry(estado: EstadoConfirmacion.invitado),
        ]),
      ),
      isTrue,
    );
  });

  test('suplente confirmado no cuenta para forzar cancelar', () {
    expect(
      debeForzarCancelarEnVezDeEliminar(
        _conv([
          _entry(estado: EstadoConfirmacion.confirmado, suplente: true),
          _entry(estado: EstadoConfirmacion.invitado),
        ]),
      ),
      isFalse,
    );
  });
}
