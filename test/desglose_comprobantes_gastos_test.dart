import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/desglose_gasto_comprobante.dart';
import 'package:matchpay/models/desglose_jugador.dart';

void main() {
  group('DesgloseJugador.parseVariablesRpc', () {
    test('array enriquecido con comprobante', () {
      final parsed = DesgloseJugador.parseVariablesRpc([
        {
          'concepto': 'Asado',
          'monto': 5000,
          'comprobante_url': 'org/gastos/asado.jpg',
        },
        {
          'concepto': 'Bebidas',
          'monto': 2000,
          'comprobante_url': null,
        },
      ]);

      expect(parsed.amounts, {
        'Asado': 5000.0,
        'Bebidas': 2000.0,
      });
      expect(parsed.gastos, hasLength(2));
      expect(parsed.gastos[0].concepto, 'Asado');
      expect(parsed.gastos[0].comprobanteUrl, 'org/gastos/asado.jpg');
      expect(parsed.gastos[0].tieneComprobante, isTrue);
      expect(parsed.gastos[1].tieneComprobante, isFalse);
    });

    test('array sin comprobante solo montos', () {
      final parsed = DesgloseJugador.parseVariablesRpc([
        {'concepto': 'Otros', 'monto': 1000},
      ]);

      expect(parsed.amounts['Otros'], 1000.0);
      expect(parsed.gastos.single.comprobanteUrl, isNull);
      expect(parsed.gastos.single.tieneComprobante, isFalse);
    });

    test('mapa legacy concepto→monto', () {
      final parsed = DesgloseJugador.parseVariablesRpc({
        'Asado': 3000,
        'Bebidas': 0,
      });

      expect(parsed.amounts, {'Asado': 3000.0});
      expect(parsed.gastos, hasLength(1));
      expect(parsed.gastos.single.comprobanteUrl, isNull);
    });

    test('null o vacío', () {
      expect(DesgloseJugador.parseVariablesRpc(null).amounts, isEmpty);
      expect(DesgloseJugador.parseVariablesRpc([]).gastos, isEmpty);
      expect(DesgloseJugador.parseVariablesRpc({}).amounts, isEmpty);
    });
  });

  group('DesgloseJugador.comprobantesGastosItems', () {
    test('incluye cancha, pelotas y variables con path', () {
      final d = DesgloseJugador(
        nombre: 'Ana',
        saldoAnterior: 0,
        cancha: 4000,
        pelotas: 1000,
        variables: const {'Asado': 2000},
        totalPartido: 7000,
        totalDebido: 7000,
        montoPagado: 0,
        saldoRestante: 7000,
        pagado: false,
        comprobanteCanchaUrl: 'org/gastos/cancha.jpg',
        comprobantePelotasUrl: null,
        gastosVariables: const [
          DesgloseGastoComprobante(
            concepto: 'Asado',
            monto: 2000,
            comprobanteUrl: 'org/gastos/asado.jpg',
          ),
          DesgloseGastoComprobante(
            concepto: 'Bebidas',
            monto: 500,
          ),
        ],
      );

      final items = d.comprobantesGastosItems(
        canchaLabel: 'Cancha',
        pelotasLabel: 'Pelotas',
      );

      expect(items.map((e) => e.label).toList(), ['Cancha', 'Asado']);
      expect(items.map((e) => e.path).toList(), [
        'org/gastos/cancha.jpg',
        'org/gastos/asado.jpg',
      ]);
    });
  });
}
