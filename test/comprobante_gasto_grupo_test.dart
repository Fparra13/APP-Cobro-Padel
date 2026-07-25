import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchpay/models/comprobante_gasto_grupo.dart';
import 'package:matchpay/models/desglose_gasto_comprobante.dart';
import 'package:matchpay/models/desglose_jugador.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/utils/formatters.dart';

DesgloseJugador _desgloseConGastos({
  required String nombre,
  String? canchaUrl,
  String? asadoUrl,
  double asadoMonto = 15000,
}) {
  return DesgloseJugador(
    nombre: nombre,
    saldoAnterior: 0,
    cancha: 5000,
    pelotas: 0,
    variables: {
      if (asadoUrl != null || asadoMonto > 0) 'Asado': asadoMonto,
    },
    totalPartido: 5000 + asadoMonto,
    totalDebido: 5000 + asadoMonto,
    montoPagado: 0,
    saldoRestante: 5000 + asadoMonto,
    pagado: false,
    comprobanteCanchaUrl: canchaUrl,
    gastosVariables: [
      if (asadoUrl != null || asadoMonto > 0)
        DesgloseGastoComprobante(
          concepto: 'Asado',
          monto: asadoMonto,
          comprobanteUrl: asadoUrl,
        ),
    ],
  );
}

DetallePartido _detalle({
  required int partidoId,
  required DateTime fecha,
}) {
  return DetallePartido(
    id: partidoId,
    partidoId: partidoId,
    jugadorId: 1,
    total: 10000,
    montoPagado: 0,
    pagado: false,
    asistio: true,
    fechaPartido: fecha,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  setUp(() {
    MoneyFormatConfig.dateLocale = 'es';
  });

  test('fromPendientes separa comprobantes por encuentro', () {
    final d1 = _detalle(
      partidoId: 1,
      fecha: DateTime(2026, 7, 27, 20),
    );
    final d2 = _detalle(
      partidoId: 2,
      fecha: DateTime(2026, 7, 30, 21),
    );
    final des1 = _desgloseConGastos(
      nombre: 'A',
      canchaUrl: 'org/gastos/cancha1.jpg',
      asadoUrl: 'org/gastos/asado1.jpg',
    );
    final des2 = _desgloseConGastos(
      nombre: 'A',
      canchaUrl: 'org/gastos/cancha2.jpg',
      asadoUrl: null,
      asadoMonto: 0,
    );

    final grupos = ComprobanteGastoGrupo.fromPendientes(
      deudas: [d2, d1], // desordenado a propósito
      desgloses: {1: des1, 2: des2},
      organizadorNombre: 'Francisco',
      canchaLabel: 'Cancha',
      pelotasLabel: 'Pelotas',
    );

    expect(grupos, hasLength(2));
    expect(grupos[0].partidoId, 1);
    expect(grupos[1].partidoId, 2);
    expect(grupos[0].lineas.map((l) => l.path).toList(), [
      'org/gastos/cancha1.jpg',
      'org/gastos/asado1.jpg',
    ]);
    expect(grupos[1].lineas.map((l) => l.path).toList(), [
      'org/gastos/cancha2.jpg',
    ]);
    expect(grupos[0].organizadorNombre, 'Francisco');
    expect(grupos[0].tituloEncuentro, contains('20:00'));
    expect(grupos[1].tituloEncuentro, contains('21:00'));
  });

  test('encuentro sin comprobantes no genera grupo', () {
    final d = _detalle(
      partidoId: 3,
      fecha: DateTime(2026, 8, 1, 19),
    );
    final des = _desgloseConGastos(nombre: 'A', asadoMonto: 1000);
    final grupos = ComprobanteGastoGrupo.fromPendientes(
      deudas: [d],
      desgloses: {3: des},
      canchaLabel: 'Cancha',
      pelotasLabel: 'Pelotas',
    );
    expect(grupos, isEmpty);
  });

  test('linea incluye monto y concepto', () {
    final grupo = ComprobanteGastoGrupo.fromDesglose(
      desglose: _desgloseConGastos(
        nombre: 'A',
        canchaUrl: 'org/c.jpg',
        asadoUrl: 'org/a.jpg',
        asadoMonto: 15000,
      ),
      detalle: _detalle(
        partidoId: 9,
        fecha: DateTime(2026, 7, 27, 20),
      ),
      organizadorNombre: 'Juan',
      canchaLabel: 'Cancha',
      pelotasLabel: 'Pelotas',
    );

    expect(grupo, isNotNull);
    expect(grupo!.lineas.first.concepto, 'Cancha');
    expect(grupo.lineas.first.monto, 5000);
    expect(grupo.lineas.last.concepto, 'Asado');
    expect(grupo.lineas.last.monto, 15000);
  });
}
