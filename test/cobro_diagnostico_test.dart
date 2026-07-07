import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/domain/cobro_diagnostico.dart';

void main() {
  group('CobroDiagnostico', () {
    test('detecta detalle sin snapshot histórico', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [
          DiagnosticoDetalleInput(
            detalleId: 10,
            partidoId: 1,
            jugadorId: '5',
            jugadorNombre: 'Ana',
            total: 8000,
            montoPagado: 0,
            pagado: false,
          ),
        ],
        historial: const [],
        jugadores: const [
          DiagnosticoJugadorInput(
            jugadorId: '5',
            nombre: 'Ana',
            saldoAcumulado: 8000,
          ),
        ],
      );

      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.detalleSinSnapshotHistorico],
        1,
      );
      expect(
        reporte.conteoPorTipo[CobroInconsistenciaTipo.partidoSinHistorial],
        1,
      );
    });

    test('detecta saldo_acumulado distinto al último saldo_nuevo', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [
          DiagnosticoDetalleInput(
            detalleId: 1,
            partidoId: 2,
            jugadorId: '7',
            total: 10000,
            montoPagado: 10000,
            pagado: true,
          ),
        ],
        historial: [
          DiagnosticoHistorialInput(
            historialId: 100,
            jugadorId: '7',
            partidoId: 2,
            saldoAnterior: 0,
            cargoPartido: 10000,
            abono: 10000,
            saldoNuevo: 0,
            fecha: DateTime(2025, 1, 1),
            concepto: 'Partido pagado',
          ),
        ],
        jugadores: const [
          DiagnosticoJugadorInput(
            jugadorId: '7',
            nombre: 'Luis',
            saldoAcumulado: 2500,
          ),
        ],
      );

      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial],
        1,
      );
      final issue = reporte.inconsistencias.firstWhere(
        (i) =>
            i.tipo == CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial,
      );
      expect(issue.datos['saldo_acumulado'], 2500);
      expect(issue.datos['saldo_esperado_historial'], 0);
    });

    test('detecta pagado que contradice CobroLogic con crédito', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [
          DiagnosticoDetalleInput(
            detalleId: 3,
            partidoId: 9,
            jugadorId: 'uuid-1',
            jugadorNombre: 'Fran',
            total: 6000,
            montoPagado: 0,
            pagado: false,
          ),
        ],
        historial: [
          DiagnosticoHistorialInput(
            historialId: 50,
            jugadorId: 'uuid-1',
            partidoId: 9,
            saldoAnterior: -8000,
            cargoPartido: 6000,
            abono: 0,
            saldoNuevo: -2000,
            fecha: DateTime(2025, 6, 1),
            concepto: 'Partido cubierto con saldo a favor',
          ),
        ],
        jugadores: const [
          DiagnosticoJugadorInput(
            jugadorId: 'uuid-1',
            saldoAcumulado: -2000,
          ),
        ],
      );

      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.pagadoContradiceCobroLogic],
        1,
      );
      final issue = reporte.inconsistencias.firstWhere(
        (i) => i.tipo == CobroInconsistenciaTipo.pagadoContradiceCobroLogic,
      );
      expect(issue.datos['partido_cerrado_neto'], isTrue);
      expect(issue.datos['pagado'], isFalse);
    });

    test('detecta monto_pagado mayor que total asignado', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [
          DiagnosticoDetalleInput(
            detalleId: 4,
            partidoId: 3,
            jugadorId: '2',
            total: 10000,
            montoPagado: 12000,
            pagado: true,
          ),
        ],
        historial: [
          DiagnosticoHistorialInput(
            historialId: 20,
            jugadorId: '2',
            partidoId: 3,
            saldoAnterior: 0,
            cargoPartido: 10000,
            abono: 12000,
            saldoNuevo: -2000,
            fecha: DateTime(2025, 3, 1),
            concepto: 'Partido pagado',
          ),
        ],
        jugadores: const [
          DiagnosticoJugadorInput(jugadorId: '2', saldoAcumulado: -2000),
        ],
      );

      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.montoPagadoSuperaCargoAsignado],
        1,
      );
    });

    test('detecta cadena histórica rota y movimiento incoherente', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [],
        historial: [
          DiagnosticoHistorialInput(
            historialId: 1,
            jugadorId: '9',
            partidoId: 1,
            saldoAnterior: 0,
            cargoPartido: 5000,
            abono: 0,
            saldoNuevo: 5000,
            fecha: DateTime(2025, 1, 1),
            concepto: 'Deuda acumulada',
          ),
          DiagnosticoHistorialInput(
            historialId: 2,
            jugadorId: '9',
            saldoAnterior: 0,
            cargoPartido: 0,
            abono: 2000,
            saldoNuevo: 1000,
            fecha: DateTime(2025, 2, 1),
            concepto: 'Abono manual',
          ),
        ],
        jugadores: const [
          DiagnosticoJugadorInput(jugadorId: '9', saldoAcumulado: 1000),
        ],
      );

      expect(
        reporte.conteoPorTipo[CobroInconsistenciaTipo.historialCadenaRota],
        greaterThanOrEqualTo(1),
      );
      expect(
        reporte.conteoPorTipo[
            CobroInconsistenciaTipo.historialMovimientoIncoherente],
        greaterThanOrEqualTo(1),
      );
    });

    test('datos consistentes no generan inconsistencias', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [
          DiagnosticoDetalleInput(
            detalleId: 1,
            partidoId: 4,
            jugadorId: '3',
            total: 6000,
            montoPagado: 6000,
            pagado: true,
          ),
        ],
        historial: [
          DiagnosticoHistorialInput(
            historialId: 11,
            jugadorId: '3',
            partidoId: 4,
            saldoAnterior: 0,
            cargoPartido: 6000,
            abono: 6000,
            saldoNuevo: 0,
            fecha: DateTime(2025, 5, 10),
            concepto: 'Partido pagado',
          ),
        ],
        jugadores: const [
          DiagnosticoJugadorInput(jugadorId: '3', saldoAcumulado: 0),
        ],
      );

      expect(reporte.tieneProblemas, isFalse);
      expect(reporte.total, 0);
    });

    test('resumenTexto incluye conteos y tipos', () {
      final reporte = CobroDiagnostico.analizar(
        detalles: const [
          DiagnosticoDetalleInput(
            partidoId: 99,
            jugadorId: '1',
            total: 1000,
            montoPagado: 0,
            pagado: false,
          ),
        ],
        historial: const [],
        jugadores: const [
          DiagnosticoJugadorInput(jugadorId: '1', saldoAcumulado: 1000),
        ],
      );

      final texto = reporte.resumenTexto();
      expect(texto, contains('Total inconsistencias:'));
      expect(texto, contains('Detalle sin snapshot'));
      expect(texto, contains('partido: 99'));
    });
  });
}
