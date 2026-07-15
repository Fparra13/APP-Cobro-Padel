import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/diagnostics/supabase_cobro_diagnostico.dart';
import 'package:matchpay/domain/cobro_diagnostico.dart';

void main() {
  group('SupabaseCobroDiagnostico.analizarFilas', () {
    test('mapea filas Supabase y detecta las 10 reglas', () {
      const jugadorId = '11111111-2222-3333-4444-555555555555';

      final reporte = SupabaseCobroDiagnostico.analizarFilas(
        detalleRows: [
          {
            'id': 10,
            'partido_id': 1,
            'jugador_id': jugadorId,
            'asistio': true,
            'total': 6000,
            'monto_pagado': 7000,
            'pagado': true,
            'profiles': {'nombre': 'Fran'},
          },
          {
            'id': 11,
            'partido_id': 2,
            'jugador_id': jugadorId,
            'asistio': true,
            'total': 6000,
            'monto_pagado': 0,
            'pagado': false,
            'profiles': {'nombre': 'Fran'},
          },
        ],
        historialRows: [
          {
            'id': 100,
            'jugador_id': jugadorId,
            'partido_id': 1,
            'saldo_anterior': 0,
            'cargo_partido': 6000,
            'abono': 7000,
            'saldo_nuevo': -1000,
            'fecha': '2025-01-01T12:00:00.000Z',
            'concepto': 'Partido pagado',
            'profiles': {'nombre': 'Fran'},
          },
          {
            'id': 101,
            'jugador_id': jugadorId,
            'partido_id': 1,
            'saldo_anterior': 0,
            'cargo_partido': 6000,
            'abono': 0,
            'saldo_nuevo': 6000,
            'fecha': '2025-01-02T12:00:00.000Z',
            'concepto': 'Duplicado',
            'profiles': {'nombre': 'Fran'},
          },
          {
            'id': 102,
            'jugador_id': jugadorId,
            'partido_id': null,
            'saldo_anterior': 0,
            'cargo_partido': 0,
            'abono': 2000,
            'saldo_nuevo': 5000,
            'fecha': '2025-02-01T12:00:00.000Z',
            'concepto': 'Abono manual',
            'profiles': {'nombre': 'Fran'},
          },
        ],
        jugadorRows: [
          {
            'id': jugadorId,
            'nombre': 'Fran',
            'saldo_acumulado': 9999,
          },
        ],
      );

      final tipos = reporte.conteoPorTipo.keys.toSet();

      expect(
        tipos,
        containsAll([
          CobroInconsistenciaTipo.montoPagadoSuperaCargoAsignado,
          CobroInconsistenciaTipo.historialSnapshotDuplicado,
          CobroInconsistenciaTipo.historialMovimientoIncoherente,
          CobroInconsistenciaTipo.historialCadenaRota,
          CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial,
          CobroInconsistenciaTipo.partidoSinHistorial,
          CobroInconsistenciaTipo.detalleSinSnapshotHistorico,
        ]),
      );
    });

    test('datos consistentes en formato Supabase no reportan problemas', () {
      const jugadorId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

      final reporte = SupabaseCobroDiagnostico.analizarFilas(
        detalleRows: [
          {
            'id': 1,
            'partido_id': 4,
            'jugador_id': jugadorId,
            'asistio': true,
            'total': 6000,
            'monto_pagado': 6000,
            'pagado': true,
            'profiles': {'nombre': 'Ana'},
          },
        ],
        historialRows: [
          {
            'id': 11,
            'jugador_id': jugadorId,
            'partido_id': 4,
            'saldo_anterior': 0,
            'cargo_partido': 6000,
            'abono': 6000,
            'saldo_nuevo': 0,
            'fecha': '2025-05-10T15:00:00.000Z',
            'concepto': 'Partido pagado',
            'profiles': {'nombre': 'Ana'},
          },
        ],
        jugadorRows: [
          {
            'id': jugadorId,
            'nombre': 'Ana',
            'saldo_acumulado': 0,
          },
        ],
      );

      expect(reporte.tieneProblemas, isFalse);
    });

    test('detecta pagado contradictorio con crédito (CobroLogic)', () {
      const jugadorId = 'cccccccc-dddd-eeee-ffff-000000000001';

      final reporte = SupabaseCobroDiagnostico.analizarFilas(
        detalleRows: [
          {
            'id': 3,
            'partido_id': 9,
            'jugador_id': jugadorId,
            'asistio': true,
            'total': 6000,
            'monto_pagado': 0,
            'pagado': false,
            'profiles': {'nombre': 'Luis'},
          },
        ],
        historialRows: [
          {
            'id': 50,
            'jugador_id': jugadorId,
            'partido_id': 9,
            'saldo_anterior': -8000,
            'cargo_partido': 6000,
            'abono': 0,
            'saldo_nuevo': -2000,
            'fecha': '2025-06-01T10:00:00.000Z',
            'concepto': 'Partido cubierto con saldo a favor',
            'profiles': {'nombre': 'Luis'},
          },
        ],
        jugadorRows: [
          {
            'id': jugadorId,
            'nombre': 'Luis',
            'saldo_acumulado': -2000,
          },
        ],
      );

      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.pagadoContradiceCobroLogic],
        1,
      );
    });

    test('detecta historial desalineado con detalle', () {
      const jugadorId = 'dddddddd-eeee-ffff-0000-111111111111';

      final reporte = SupabaseCobroDiagnostico.analizarFilas(
        detalleRows: [
          {
            'id': 5,
            'partido_id': 7,
            'jugador_id': jugadorId,
            'asistio': true,
            'total': 10000,
            'monto_pagado': 4000,
            'pagado': false,
            'profiles': {'nombre': 'Pablo'},
          },
        ],
        historialRows: [
          {
            'id': 70,
            'jugador_id': jugadorId,
            'partido_id': 7,
            'saldo_anterior': 0,
            'cargo_partido': 10000,
            'abono': 0,
            'saldo_nuevo': 10000,
            'fecha': '2025-04-01T10:00:00.000Z',
            'concepto': 'Deuda acumulada',
            'profiles': {'nombre': 'Pablo'},
          },
        ],
        jugadorRows: [
          {
            'id': jugadorId,
            'nombre': 'Pablo',
            'saldo_acumulado': 6000,
          },
        ],
      );

      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.historialDetalleDesalineado],
        1,
      );
    });

    test('detecta valores imposibles', () {
      const jugadorId = 'eeeeeeee-ffff-0000-1111-222222222222';

      final reporte = SupabaseCobroDiagnostico.analizarFilas(
        detalleRows: [
          {
            'id': 8,
            'partido_id': 3,
            'jugador_id': jugadorId,
            'asistio': true,
            'total': -100,
            'monto_pagado': -50,
            'pagado': false,
          },
        ],
        historialRows: const [],
        jugadorRows: [
          {
            'id': jugadorId,
            'nombre': 'Roto',
            'saldo_acumulado': 0,
          },
        ],
      );

      expect(
        reporte.conteoPorTipo[CobroInconsistenciaTipo.valorImposible],
        greaterThanOrEqualTo(2),
      );
    });

    test(
      'Demo 01 filas Supabase: dos orgs no netean ni rompen cadena',
      () {
        const demo = '11111111-aaaa-bbbb-cccc-dddddddddddd';
        const francisco = '22222222-aaaa-bbbb-cccc-ffffffffffff';
        const orgB = '33333333-aaaa-bbbb-cccc-ffffffffffff';

        final reporte = SupabaseCobroDiagnostico.analizarFilas(
          detalleRows: const [],
          historialRows: [
            {
              'id': 1,
              'jugador_id': demo,
              'organizador_id': francisco,
              'partido_id': 10,
              'saldo_anterior': 0,
              'cargo_partido': 7000,
              'abono': 0,
              'saldo_nuevo': 7000,
              'fecha': '2026-01-01T12:00:00.000Z',
              'concepto': 'Deuda Francisco',
              'profiles': {'nombre': 'Demo 01'},
            },
            {
              'id': 2,
              'jugador_id': demo,
              'organizador_id': orgB,
              'partido_id': 11,
              'saldo_anterior': 0,
              'cargo_partido': 0,
              'abono': 3000,
              'saldo_nuevo': -3000,
              'fecha': '2026-01-02T12:00:00.000Z',
              'concepto': 'Crédito Org B',
              'profiles': {'nombre': 'Demo 01'},
            },
          ],
          jugadorRows: [
            {
              'jugador_id': demo,
              'organizador_id': francisco,
              'nombre': 'Demo 01',
              'saldo_acumulado': 7000,
            },
            {
              'jugador_id': demo,
              'organizador_id': orgB,
              'nombre': 'Demo 01',
              'saldo_acumulado': -3000,
            },
          ],
        );

        expect(reporte.tieneProblemas, isFalse);
        expect(
          reporte.conteoPorTipo[CobroInconsistenciaTipo.historialCadenaRota],
          isNull,
        );
      },
    );

    test(
      'sin organizador_id (legacy) mezcla cadenas del mismo jugador',
      () {
        // Regresión: si el loader omitiera organizador_id, el motor netearía.
        const demo = '44444444-aaaa-bbbb-cccc-dddddddddddd';

        final reporte = SupabaseCobroDiagnostico.analizarFilas(
          detalleRows: const [],
          historialRows: [
            {
              'id': 1,
              'jugador_id': demo,
              'partido_id': 10,
              'saldo_anterior': 0,
              'cargo_partido': 7000,
              'abono': 0,
              'saldo_nuevo': 7000,
              'fecha': '2026-01-01T12:00:00.000Z',
              'concepto': 'Org A',
            },
            {
              'id': 2,
              'jugador_id': demo,
              'partido_id': 11,
              'saldo_anterior': 0,
              'cargo_partido': 0,
              'abono': 3000,
              'saldo_nuevo': -3000,
              'fecha': '2026-01-02T12:00:00.000Z',
              'concepto': 'Org B',
            },
          ],
          jugadorRows: [
            {
              'id': demo,
              'nombre': 'Demo',
              'saldo_acumulado': 4000,
            },
          ],
        );

        expect(
          reporte.conteoPorTipo[CobroInconsistenciaTipo.historialCadenaRota],
          greaterThanOrEqualTo(1),
        );
      },
    );
  });
}
