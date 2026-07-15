import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/cuenta_saldo.dart';
import 'package:matchpay/models/desglose_jugador.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/utils/cobro_jugador_ui.dart';

DetallePartido _deuda({
  required int partidoId,
  double total = 15000,
  double montoPagado = 5000,
  bool pagado = false,
  String? comprobanteUrl,
  bool? comprobanteValidado,
}) {
  return DetallePartido(
    partidoId: partidoId,
    jugadorSupabaseId: 'jugador-1',
    asistio: true,
    total: total,
    montoPagado: montoPagado,
    pagado: pagado,
    comprobanteUrl: comprobanteUrl,
    comprobanteValidado: comprobanteValidado,
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

  test(
    'totalPendienteCobros con crédito o al día NO suma brutos de partidos',
    () {
      final deudas = [
        _deuda(partidoId: 52, total: 12000, montoPagado: 0, pagado: true),
        _deuda(partidoId: 53, total: 12000, montoPagado: 0, pagado: true),
      ];
      const desgloses = <int, DesgloseJugador?>{};

      expect(
        totalPendienteCobros(
          deudas,
          desgloses,
          saldoAcumuladoJugador: -26000,
        ),
        0,
      );
      expect(
        totalPendienteCobros(
          deudas,
          desgloses,
          saldoAcumuladoJugador: 0,
        ),
        0,
      );
    },
  );

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

  test(
    'cobrosVisiblesJugador con crédito no muestra ficha de pago reutilizable',
    () {
      final deudas = [
        _deuda(partidoId: 52, total: 12000, montoPagado: 0, pagado: true),
        _deuda(partidoId: 53, total: 12000, montoPagado: 0, pagado: true),
      ];
      final visibles = cobrosVisiblesJugador(
        deudas: deudas,
        desgloses: const {},
        saldoAcumuladoJugador: -26000,
      );
      expect(visibles.ancla, isNull);
      expect(visibles.otros, isEmpty);
    },
  );

  test(
    'cobrosVisiblesJugador con crédito solo deja comprobante en revisión',
    () {
      final deudas = [
        _deuda(partidoId: 52, total: 12000, montoPagado: 0, pagado: true),
        _deuda(
          partidoId: 53,
          total: 12000,
          montoPagado: 0,
          pagado: false,
          comprobanteUrl: 'path/comp.jpg',
          comprobanteValidado: false,
        ),
      ];
      final visibles = cobrosVisiblesJugador(
        deudas: deudas,
        desgloses: const {},
        saldoAcumuladoJugador: -5000,
      );
      expect(visibles.ancla?.partidoId, 53);
      expect(visibles.otros, isEmpty);
    },
  );

  test('mostrarHeroCobroPendiente no abre tarjeta con \$0 y sin revisión', () {
    expect(
      mostrarHeroCobroPendiente(
        totalPendiente: 0,
        comprobanteEnRevision: false,
      ),
      isFalse,
    );
    expect(
      mostrarHeroCobroPendiente(
        totalPendiente: 5000,
        comprobanteEnRevision: false,
      ),
      isTrue,
    );
    expect(
      mostrarHeroCobroPendiente(
        totalPendiente: 0,
        comprobanteEnRevision: true,
      ),
      isTrue,
    );
  });

  test('cobrosParaResumenDeportes solo usa ancla y otros visibles', () {
    final ancla = _deuda(partidoId: 1);
    final otro = _deuda(partidoId: 2);
    expect(
      cobrosParaResumenDeportes(ancla: null, otros: [otro]),
      isEmpty,
    );
    expect(
      cobrosParaResumenDeportes(ancla: ancla, otros: [otro]).map((d) => d.partidoId),
      [1, 2],
    );
  });

  group('multi-org — sin netear (Demo 01 / 02)', () {
    test('totalDeudaDesdeCuentas Demo 01 → 7000 no 4000', () {
      const cuentas = [
        CuentaSaldo(
          organizadorId: 'francisco',
          nombreOrganizador: 'Francisco',
          saldoAcumulado: 7000,
        ),
        CuentaSaldo(
          organizadorId: 'org-b',
          nombreOrganizador: 'Org B',
          saldoAcumulado: -3000,
        ),
      ];
      expect(totalDeudaDesdeCuentas(cuentas), 7000);
      expect(totalCreditoDesdeCuentas(cuentas), 3000);
      expect(cuentaConMayorDeuda(cuentas)?.organizadorId, 'francisco');
    });

    test('totalDeudaDesdeCuentas Demo 02 → 4000 no 2000', () {
      const cuentas = [
        CuentaSaldo(
          organizadorId: 'francisco',
          nombreOrganizador: 'Francisco',
          saldoAcumulado: -2000,
        ),
        CuentaSaldo(
          organizadorId: 'org-b',
          nombreOrganizador: 'Org B',
          saldoAcumulado: 4000,
        ),
      ];
      expect(totalDeudaDesdeCuentas(cuentas), 4000);
      expect(cuentaConMayorDeuda(cuentas)?.organizadorId, 'org-b');
    });

    test('deudasDeOrganizador no mezcla partidos de otro org', () {
      final deudas = [
        DetallePartido(
          partidoId: 1,
          jugadorSupabaseId: 'j1',
          total: 7000,
          organizadorId: 'francisco',
        ),
        DetallePartido(
          partidoId: 2,
          jugadorSupabaseId: 'j1',
          total: 4000,
          organizadorId: 'org-b',
        ),
      ];
      expect(deudasDeOrganizador(deudas, 'francisco').single.partidoId, 1);
      expect(deudasDeOrganizador(deudas, 'org-b').single.partidoId, 2);
    });
  });
}
