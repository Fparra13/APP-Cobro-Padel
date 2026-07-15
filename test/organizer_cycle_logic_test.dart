import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/organizer_cycle_logic.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/models/partido.dart';
import 'package:matchpay/repositories/partido_repository.dart';
import 'package:matchpay/widgets/organizer_cycle_hero.dart';

DetallePartido _detalle({
  bool asistio = true,
  double total = 1400,
  double montoPagado = 0,
  bool pagado = false,
  String? comprobanteUrl,
  double? montoPagoDeclarado,
  String? jugadorSupabaseId,
}) {
  return DetallePartido(
    partidoId: 1,
    jugadorSupabaseId: jugadorSupabaseId,
    asistio: asistio,
    total: total,
    montoPagado: montoPagado,
    pagado: pagado,
    comprobanteUrl: comprobanteUrl,
    montoPagoDeclarado: montoPagoDeclarado,
  );
}

PartidoCompleto _partido(
  List<DetallePartido> detalles, {
  Map<String, double> saldos = const {},
}) {
  final fecha = DateTime(2026, 7, 3, 21, 9);
  return PartidoCompleto(
    partido: Partido(fecha: fecha, createdAt: fecha),
    detalles: detalles,
    saldoAnteriorPorJugador: saldos,
  );
}

void main() {
  test('comprobante pendiente sin deuda monetaria no cuenta como cobro abierto', () {
    final d = _detalle(
      total: 1400,
      montoPagado: 1400,
      pagado: false,
      comprobanteUrl: 'path/comprobante.jpg',
      montoPagoDeclarado: 1400,
    );
    expect(detalleCobroOrganizadorPendiente(d), isFalse);
  });

  test('deuda monetaria sí cuenta como cobro abierto', () {
    final d = _detalle(total: 1400, montoPagado: 0, pagado: false);
    expect(detalleCobroOrganizadorPendiente(d), isTrue);
  });

  test('detalle marcado pagado con saldo a favor parcial sigue pendiente', () {
    final d = _detalle(
      total: 10000,
      montoPagado: 0,
      pagado: true,
      jugadorSupabaseId: 'j1',
    );
    expect(
      detalleCobroOrganizadorPendiente(
        d,
        saldoAnteriorPartido: -5000,
      ),
      isTrue,
    );
    expect(pendienteOrganizadorDetalle(d, saldoAnteriorPartido: -5000), 5000);
  });

  test('partido cerrado cuando todos los asistentes pagaron neto', () {
    final pc = _partido([
      _detalle(total: 1400, montoPagado: 1400, pagado: true),
      _detalle(
        total: 10000,
        montoPagado: 5000,
        pagado: true,
        jugadorSupabaseId: 'j2',
      ),
    ], saldos: {'j2': -5000});
    expect(partidoOrganizadorCobrosCerrados(pc), isTrue);
    expect(cobrosOrganizadorPendientes(pc), isEmpty);
  });

  test('prioriza el partido más antiguo con cobros abiertos', () {
    final viejo = _partido(
      [_detalle(total: 1400, pagado: false, jugadorSupabaseId: 'j-old')],
      saldos: {'j-old': 0},
    );
    final nuevo = PartidoCompleto(
      partido: Partido(
        fecha: DateTime(2026, 7, 10),
        createdAt: DateTime(2026, 7, 10),
      ),
      detalles: [
        _detalle(total: 900, pagado: false, jugadorSupabaseId: 'j-new'),
      ],
      saldoAnteriorPorJugador: const {'j-new': 0},
    );
    final elegido = partidoConCobrosPendientes([nuevo, viejo]);
    expect(elegido, viejo);
    expect(montoTotalCobrosPendientes([nuevo, viejo]), 2300);
    expect(partidosConCobrosPendientes([nuevo, viejo]).length, 2);
  });

  test('sin snapshot de ledger no inventa cobro abierto', () {
    final pc = _partido([
      _detalle(total: 1400, pagado: false, jugadorSupabaseId: 'j1'),
    ]);
    expect(cobrosOrganizadorPendientes(pc), isEmpty);
    expect(partidoConCobrosPendientes([pc]), isNull);
  });

  test('partido fallback cuando resumen tiene deuda pero detalle bruto pagado', () {
    final pc = _partido([
      _detalle(
        total: 10000,
        pagado: true,
        jugadorSupabaseId: 'uuid-deudor',
      ),
      _detalle(
        total: 10000,
        montoPagado: 10000,
        pagado: true,
        jugadorSupabaseId: 'uuid-ok',
      ),
    ], saldos: {'uuid-deudor': -5000});

    expect(partidoConCobrosPendientes([pc]), isNotNull);
    expect(cobrosOrganizadorPendientes(pc).length, 1);

    final resumen = ResumenJugador(
      jugador: Jugador(
        nombre: 'Ana',
        supabaseId: 'uuid-deudor',
        createdAt: DateTime(2026),
      ),
      saldoActual: 5000,
      partidosJugados: 1,
      totalPendiente: 0,
    );
    expect(
      partidoFallbackDeudaGrupo([pc], [resumen]),
      pc,
    );
  });

  test('un jugador en varios partidos cuenta una vez (no por detalle)', () {
    const jid = 'francisco-uuid';
    final p52 = _partido(
      [_detalle(
        total: 5000,
        montoPagado: 5000,
        pagado: true,
        jugadorSupabaseId: jid,
      )],
      saldos: {jid: 10000},
    );
    final p53 = _partido(
      [_detalle(
        total: 5000,
        montoPagado: 5000,
        pagado: true,
        jugadorSupabaseId: jid,
      )],
      saldos: {jid: 15000},
    );
    final p54 = _partido(
      [_detalle(
        total: 10000,
        montoPagado: 5000,
        pagado: false,
        jugadorSupabaseId: jid,
      )],
      saldos: {jid: 15000},
    );
    final partidos = [p52, p53, p54];

    expect(jugadoresPendientesUnicos(partidos), 1);
    expect(partidosConCobrosPendientes(partidos).length, 3);
    expect(
      montoTotalCobrosPendientes(partidos),
      greaterThan(5000),
    );

    final resumen = ResumenJugador(
      jugador: Jugador(
        nombre: 'Francisco',
        supabaseId: jid,
        createdAt: DateTime(2026),
      ),
      saldoActual: 5000,
      partidosJugados: 4,
      totalPendiente: 0,
    );
    final snap = OrganizerCycleSnapshot.resolve(
      convocatorias: const [],
      partidosJugadosRecientes: partidos,
      resumenesGrupo: [resumen],
    );

    expect(snap.phase, OrganizerCyclePhase.collecting);
    expect(snap.partidosCobroPendiente, 3);
    expect(snap.jugadoresCobroPendiente, 1);
    expect(snap.montoCobroPendienteTotal, 5000);
  });
}
