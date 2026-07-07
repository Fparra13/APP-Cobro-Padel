import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/diagnostics/cobro_diagnostico_comparador.dart';
import 'package:matchpay/domain/cobro_diagnostico.dart';

void main() {
  group('CobroDiagnosticoComparador', () {
    CobroInconsistencia _issue(
      CobroInconsistenciaTipo tipo, {
      int? partidoId,
      String? jugadorId,
    }) =>
        CobroInconsistencia(
          tipo: tipo,
          partidoId: partidoId,
          jugadorId: jugadorId,
          mensaje: 'test',
        );

    test('identifica inconsistencias solo en una base', () {
      final local = CobroDiagnosticoReporte(
        generadoEn: DateTime(2025),
        inconsistencias: [
          _issue(
            CobroInconsistenciaTipo.partidoSinHistorial,
            partidoId: 1,
          ),
        ],
      );
      final remoto = CobroDiagnosticoReporte(
        generadoEn: DateTime(2025),
        inconsistencias: [
          _issue(
            CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial,
            jugadorId: 'u1',
          ),
        ],
      );

      final cmp = CobroDiagnosticoComparador.comparar(local: local, remoto: remoto);

      expect(cmp.basesEquivalentes, isFalse);
      expect(cmp.clavesSoloLocal.length, 1);
      expect(cmp.clavesSoloRemoto.length, 1);
      expect(cmp.clavesEnAmbos, isEmpty);
    });

    test('bases equivalentes cuando coinciden claves', () {
      final issue = _issue(
        CobroInconsistenciaTipo.detalleSinSnapshotHistorico,
        partidoId: 5,
        jugadorId: 'abc',
      );
      final reporte = CobroDiagnosticoReporte(
        generadoEn: DateTime(2025),
        inconsistencias: [issue],
      );

      final cmp = CobroDiagnosticoComparador.comparar(
        local: reporte,
        remoto: reporte,
      );

      expect(cmp.basesEquivalentes, isTrue);
      expect(cmp.clavesEnAmbos.length, 1);
    });
  });
}
