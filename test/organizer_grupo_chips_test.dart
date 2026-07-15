import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/organizer_cycle_logic.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/repositories/partido_repository.dart';

ResumenJugador _r(double saldo, {String nombre = 'J'}) {
  return ResumenJugador(
    jugador: Jugador(
      nombre: nombre,
      saldoAcumulado: saldo,
      createdAt: DateTime(2026),
    ),
    saldoActual: saldo,
    partidosJugados: 1,
    totalPendiente: 0,
  );
}

void main() {
  test('Al día incluye saldo a favor (sin renombrar el chip)', () {
    final resumenes = [
      _r(5000, nombre: 'Deudor'),
      _r(-12000, nombre: 'Org'),
      _r(0, nombre: 'Cero'),
    ];
    expect(jugadoresConDeudaGrupo(resumenes), 1);
    expect(jugadoresAlDiaGrupo(resumenes), 2); // crédito + cero
    expect(jugadoresConCreditoGrupo(resumenes), 1);
  });

  test('organizador solo con crédito cuenta en Al día', () {
    final resumenes = [_r(-50900, nombre: 'Francisco')];
    expect(jugadoresAlDiaGrupo(resumenes), 1);
    expect(jugadoresConDeudaGrupo(resumenes), 0);
  });

  test('filtro Al día incluye saldo a favor', () {
    final resumenes = [
      _r(-8000, nombre: 'Credito'),
      _r(0, nombre: 'Cero'),
      _r(3000, nombre: 'Deuda'),
    ];
    final alDia = resumenes.where((r) => !r.tieneDeuda).toList();
    expect(alDia.map((r) => r.jugador.nombre), ['Credito', 'Cero']);
  });
}
