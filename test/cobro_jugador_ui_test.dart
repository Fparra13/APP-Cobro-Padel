import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/desglose_jugador.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/utils/cobro_jugador_ui.dart';

DetallePartido _deuda({
  required int partidoId,
  double total = 15000,
  double montoPagado = 5000,
}) {
  return DetallePartido(
    partidoId: partidoId,
    jugadorSupabaseId: 'jugador-1',
    asistio: true,
    total: total,
    montoPagado: montoPagado,
    pagado: false,
  );
}

void main() {
  test('totalPendienteCobros usa saldo_acumulado y no suma por partido', () {
    final deudas = [
      _deuda(partidoId: 52, total: 5000, montoPagado: 5000),
      _deuda(partidoId: 53, total: 5000, montoPagado: 5000),
      _deuda(partidoId: 54, total: 10000, montoPagado: 5000),
    ];
    const desgloses = <int, DesgloseJugador?>{};

    final sinSsot = totalPendienteCobros(
      deudas,
      desgloses,
      saldosAnterioresPorPartido: const {
        52: 0,
        53: 10000,
        54: 15000,
      },
    );
    expect(sinSsot, greaterThan(5000));

    final conSsot = totalPendienteCobros(
      deudas,
      desgloses,
      saldoAcumuladoJugador: 5000,
    );
    expect(conSsot, 5000);
  });

  test('cobrosVisiblesJugador oculta partidos con cargo saldado', () {
    final deudas = [
      _deuda(partidoId: 52, total: 5000, montoPagado: 5000),
      _deuda(partidoId: 53, total: 5000, montoPagado: 5000),
      _deuda(partidoId: 54, total: 10000, montoPagado: 5000),
    ];
    const desgloses = <int, DesgloseJugador?>{};
    final visibles = cobrosVisiblesJugador(
      deudas: deudas,
      desgloses: desgloses,
      saldosAnterioresPorPartido: const {
        52: 0,
        53: 10000,
        54: 15000,
      },
      saldoAcumuladoJugador: 5000,
    );
    expect(visibles.ancla, isNotNull);
    expect(visibles.otros, isEmpty);
    expect(visibles.ancla!.partidoId, 52);
  });
}
