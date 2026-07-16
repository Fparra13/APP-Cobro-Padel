import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/desglose_jugador.dart';

DesgloseJugador _desglose({
  double saldoAnterior = 3000,
  double totalPartido = 10000,
  double montoPagado = 11000,
  double? saldoCuenta,
}) {
  final totalDebido = saldoAnterior > 0
      ? saldoAnterior + totalPartido
      : totalPartido;
  final saldoRestante = saldoAnterior + totalPartido - montoPagado;
  return DesgloseJugador(
    nombre: 'Diego',
    saldoAnterior: saldoAnterior,
    cancha: totalPartido,
    pelotas: 0,
    variables: const {},
    totalPartido: totalPartido,
    totalDebido: totalDebido,
    montoPagado: montoPagado,
    saldoRestante: saldoRestante,
    pagado: false,
    saldoAcumuladoCuenta: saldoCuenta,
  );
}

void main() {
  test('pendiente de partido puede ser > 0 aunque la cuenta esté a favor', () {
    final d = _desglose(saldoCuenta: -1000);
    expect(d.pendientePartido, 2000);
    expect(d.creditoCuenta, 1000);
    expect(d.pendienteOrganizador, 0);
    expect(d.tieneCobroPendienteOrganizador, isFalse);
    expect(d.alDiaOrganizador, isTrue);
  });

  test('sin saldo de cuenta, usa pendiente del partido', () {
    final d = _desglose(saldoCuenta: null);
    expect(d.pendienteOrganizador, 2000);
    expect(d.tieneCobroPendienteOrganizador, isTrue);
    expect(d.alDiaOrganizador, isFalse);
  });

  test('cuenta con deuda usa SSOT de cuenta', () {
    final d = _desglose(saldoCuenta: 5000, montoPagado: 0);
    expect(d.pendienteOrganizador, 5000);
    expect(d.tieneCobroPendienteOrganizador, isTrue);
  });
}
