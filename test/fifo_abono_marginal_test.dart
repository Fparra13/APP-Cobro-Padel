import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_logic.dart';

void main() {
  group('pendienteFifoDetalle — no doble cuenta deuda anterior', () {
    test('deuda anterior positiva: solo hueco del cargo', () {
      // Partido 2: snap +3000, cargo 10000, abonado 10000 → cubierto en FIFO
      expect(
        CobroLogic.pendienteFifoDetalle(
          saldoAnterior: 3000,
          cargoPartido: 10000,
          montoPagadoEnPartido: 10000,
        ),
        0,
      );
      expect(
        CobroLogic.partidoCubiertoFifo(
          saldoAnterior: 3000,
          cargoPartido: 10000,
          montoPagadoEnPartido: 10000,
        ),
        isTrue,
      );
      // Neto histórico seguiría mostrando 3000 (bug viejo).
      expect(
        CobroLogic.obtenerPendientePartido(
          saldoAnteriorAlPartido: 3000,
          cargoPartido: 10000,
          montoPagadoEnPartido: 10000,
        ),
        3000,
      );
    });

    test('waterfall Diego: 3500 + 10000 + 4000', () {
      // Partido 1 tras abono 3500
      expect(
        CobroLogic.pendienteFifoDetalle(
          saldoAnterior: 0,
          cargoPartido: 6500,
          montoPagadoEnPartido: 3500,
        ),
        3000,
      );

      // Pago 10000: primero cierra p1 (3000), luego 7000 a p2
      var resto = 10000.0;
      final p1 = CobroLogic.pendienteFifoDetalle(
        saldoAnterior: 0,
        cargoPartido: 6500,
        montoPagadoEnPartido: 3500,
      );
      final a1 = resto >= p1 ? p1 : resto;
      resto -= a1;
      final p1Paid = 3500 + a1;
      expect(p1Paid, 6500);
      expect(resto, 7000);

      final p2 = CobroLogic.pendienteFifoDetalle(
        saldoAnterior: 3000,
        cargoPartido: 10000,
        montoPagadoEnPartido: 0,
      );
      expect(p2, 10000); // no 13000
      final a2 = resto >= p2 ? p2 : resto;
      resto -= a2;
      expect(a2, 7000);
      expect(resto, 0);
      final p2Paid = 0 + a2;

      // Pago 4000: cierra p2 (faltan 3000) → crédito 1000 en cuenta
      resto = 4000;
      final p2b = CobroLogic.pendienteFifoDetalle(
        saldoAnterior: 3000,
        cargoPartido: 10000,
        montoPagadoEnPartido: p2Paid,
      );
      expect(p2b, 3000);
      final a2b = resto >= p2b ? p2b : resto;
      resto -= a2b;
      expect(a2b, 3000);
      expect(resto, 1000); // queda a favor en cuenta
      expect(
        CobroLogic.partidoCubiertoFifo(
          saldoAnterior: 3000,
          cargoPartido: 10000,
          montoPagadoEnPartido: p2Paid + a2b,
        ),
        isTrue,
      );
    });

    test('crédito previo sí reduce el cargo de este partido', () {
      expect(
        CobroLogic.pendienteFifoDetalle(
          saldoAnterior: -5000,
          cargoPartido: 10000,
          montoPagadoEnPartido: 0,
        ),
        5000,
      );
    });
  });
}
