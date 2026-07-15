import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_notificacion_logic.dart';
import 'package:matchpay/models/desglose_jugador.dart';
import 'package:matchpay/models/detalle_partido.dart';

DetallePartido _detalle({
  required double total,
  required bool pagado,
  double montoPagado = 0,
}) {
  return DetallePartido(
    partidoId: 1,
    jugadorSupabaseId: 'j1',
    asistio: true,
    total: total,
    montoPagado: montoPagado,
    pagado: pagado,
  );
}

DesgloseJugador _desglose({
  required double saldoAnterior,
  required double totalPartido,
  double montoPagado = 0,
}) {
  return DesgloseJugador(
    nombre: 'Test',
    saldoAnterior: saldoAnterior,
    cancha: totalPartido,
    pelotas: 0,
    variables: const {},
    totalPartido: totalPartido,
    totalDebido: totalPartido + (saldoAnterior > 0 ? saldoAnterior : 0),
    montoPagado: montoPagado,
    saldoRestante: saldoAnterior + totalPartido - montoPagado,
    pagado: pagadoDesde(saldoAnterior, totalPartido, montoPagado),
  );
}

bool pagadoDesde(double saldoAnt, double cargo, double pago) {
  final pendiente = saldoAnt + cargo - pago;
  return pendiente <= 0.005;
}

void main() {
  test('cobro pendiente sin snapshot notifica si aún no está pagado', () {
    final d = _detalle(total: 12000, pagado: false);
    expect(
      debeNotificarCobroPendiente(detalle: d),
      isTrue,
    );
  });

  test('cobro cubierto con favor no se trata como pendiente', () {
    final d = _detalle(total: 12000, pagado: true, montoPagado: 0);
    final dsg = _desglose(saldoAnterior: -20000, totalPartido: 12000);
    expect(dsg.saldoFavorAplicado, greaterThan(0.005));
    expect(dsg.pendientePartido, lessThanOrEqualTo(0.005));
    expect(
      debeNotificarCobroPendiente(
        detalle: d,
        desglose: dsg,
        snapshotSaldoAnterior: -20000,
      ),
      isFalse,
    );
    expect(
      debeNotificarCobroCubiertoConFavor(
        detalle: d,
        desglose: dsg,
      ),
      isTrue,
    );
  });

  test('cubierto con favor sin snapshot usa desglose', () {
    final d = _detalle(total: 8000, pagado: true);
    final dsg = _desglose(saldoAnterior: -15000, totalPartido: 8000);
    expect(
      debeNotificarCobroCubiertoConFavor(detalle: d, desglose: dsg),
      isTrue,
    );
  });

  test('organizador con deuda abierta sí notifica', () {
    final d = _detalle(total: 9000, pagado: false);
    final dsg = _desglose(saldoAnterior: 0, totalPartido: 9000);
    expect(
      debeNotificarCobroPendiente(detalle: d, desglose: dsg),
      isTrue,
    );
    expect(montoNotificacionCobroPendiente(detalle: d, desglose: dsg), 9000);
  });
}
