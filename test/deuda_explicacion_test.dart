import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/deuda_explicacion.dart';
import 'package:matchpay/models/saldo_historico.dart';

SaldoHistorico _mov({
  required int partidoId,
  required double saldoAnterior,
  required double cargo,
  double abono = 0,
  required double saldoNuevo,
}) {
  return SaldoHistorico(
    partidoId: partidoId,
    saldoAnterior: saldoAnterior,
    cargoPartido: cargo,
    abono: abono,
    saldoNuevo: saldoNuevo,
    fecha: DateTime(2026, 7, 6, 20, 15),
    concepto: 'Partido',
  );
}

void main() {
  test('crédito a favor + cargo explica deuda actual (caso Francisco)', () {
    final historial = [
      _mov(partidoId: 51, saldoAnterior: 0, cargo: 10000, saldoNuevo: 10000),
      _mov(partidoId: 52, saldoAnterior: 10000, cargo: 5000, saldoNuevo: 15000),
      _mov(
        partidoId: 53,
        saldoAnterior: 15000,
        cargo: 5000,
        abono: 5000,
        saldoNuevo: 15000,
      ),
      SaldoHistorico(
        saldoAnterior: 15000,
        cargoPartido: 0,
        abono: 20000,
        saldoNuevo: -5000,
        fecha: DateTime(2026, 7, 6, 21),
        concepto: 'Abono',
      ),
      _mov(
        partidoId: 54,
        saldoAnterior: -5000,
        cargo: 10000,
        saldoNuevo: 5000,
      ),
    ];

    final exp = explicarDeudaJugador(
      saldoAcumulado: 5000,
      historial: historial,
    );

    expect(exp, isNotNull);
    expect(exp!.deudaActual, 5000);
    expect(exp.partidoIdContexto, 54);
    expect(
      exp.lineas.map((l) => l.labelKey),
      containsAll([
        'deudaSimpleMatchAmount',
        'deudaSimpleCredit',
      ]),
    );
    expect(explicacionCuadraConSaldo(
      explicacion: exp,
      saldoAcumulado: 5000,
    ), isTrue);
  });

  test('sin deuda devuelve null', () {
    expect(
      explicarDeudaJugador(saldoAcumulado: 0, historial: const []),
      isNull,
    );
  });

  test('abono al registrar ignora pagos globales posteriores', () {
    final historial = [
      _mov(partidoId: 51, saldoAnterior: 0, cargo: 10000, saldoNuevo: 10000),
      _mov(partidoId: 52, saldoAnterior: 10000, cargo: 5000, saldoNuevo: 15000),
      _mov(
        partidoId: 53,
        saldoAnterior: 15000,
        cargo: 5000,
        abono: 5000,
        saldoNuevo: 15000,
      ),
      SaldoHistorico(
        saldoAnterior: 15000,
        cargoPartido: 0,
        abono: 20000,
        saldoNuevo: -5000,
        fecha: DateTime(2026, 7, 6, 21),
        concepto: 'Abono',
      ),
      _mov(
        partidoId: 54,
        saldoAnterior: -5000,
        cargo: 10000,
        saldoNuevo: 5000,
      ),
    ];

    final abonos = abonoAlRegistrarPorPartido(historial);
    expect(abonos[51], 0);
    expect(abonos[52], 0);
    expect(abonos[53], 5000);
    expect(abonos[54], 0);
  });
}
