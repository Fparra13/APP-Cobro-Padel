import '../domain/cobro_diagnostico.dart';

/// Comparación entre dos reportes de diagnóstico (p. ej. SQLite vs Supabase).
class CobroDiagnosticoComparacion {
  final CobroDiagnosticoReporte local;
  final CobroDiagnosticoReporte remoto;
  final Set<String> clavesSoloLocal;
  final Set<String> clavesSoloRemoto;
  final Set<String> clavesEnAmbos;

  const CobroDiagnosticoComparacion({
    required this.local,
    required this.remoto,
    required this.clavesSoloLocal,
    required this.clavesSoloRemoto,
    required this.clavesEnAmbos,
  });

  Map<CobroInconsistenciaTipo, int> get conteoSoloLocal =>
      _conteoPorTipo(clavesSoloLocal, local.inconsistencias);

  Map<CobroInconsistenciaTipo, int> get conteoSoloRemoto =>
      _conteoPorTipo(clavesSoloRemoto, remoto.inconsistencias);

  Map<CobroInconsistenciaTipo, int> get conteoEnAmbos =>
      _conteoPorTipo(clavesEnAmbos, local.inconsistencias);

  bool get basesEquivalentes =>
      local.total == remoto.total &&
      clavesSoloLocal.isEmpty &&
      clavesSoloRemoto.isEmpty;

  String resumenTexto() {
    final buf = StringBuffer()
      ..writeln('Comparación diagnóstico SQLite vs Supabase')
      ..writeln('Local:  ${local.total} inconsistencias')
      ..writeln('Remoto: ${remoto.total} inconsistencias')
      ..writeln('Solo en local:  ${clavesSoloLocal.length}')
      ..writeln('Solo en remoto: ${clavesSoloRemoto.length}')
      ..writeln('En ambas bases: ${clavesEnAmbos.length}')
      ..writeln();

    void escribirBloque(String titulo, Map<CobroInconsistenciaTipo, int> map) {
      if (map.isEmpty) return;
      buf.writeln(titulo);
      final entries = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        buf.writeln('  - ${e.key.etiqueta}: ${e.value}');
      }
      buf.writeln();
    }

    escribirBloque('Solo en local (por tipo):', conteoSoloLocal);
    escribirBloque('Solo en remoto (por tipo):', conteoSoloRemoto);
    escribirBloque('Coinciden en ambas (por tipo):', conteoEnAmbos);

    if (basesEquivalentes) {
      buf.writeln('Resultado: bases equivalentes según claves de inconsistencia.');
    } else {
      buf.writeln(
        'Resultado: hay diferencias entre bases (no implica bug de sync; '
        'pueden ser datos distintos o IDs no alineados).',
      );
    }

    return buf.toString();
  }

  static Map<CobroInconsistenciaTipo, int> _conteoPorTipo(
    Set<String> claves,
    List<CobroInconsistencia> items,
  ) {
    final map = <CobroInconsistenciaTipo, int>{};
    for (final i in items) {
      if (!claves.contains(CobroDiagnosticoComparador.clave(i))) continue;
      map[i.tipo] = (map[i.tipo] ?? 0) + 1;
    }
    return map;
  }
}

class CobroDiagnosticoComparador {
  CobroDiagnosticoComparador._();

  static String clave(CobroInconsistencia i) =>
      '${i.tipo.name}|p${i.partidoId}|j${i.jugadorId}|d${i.detalleId}|h${i.historialId}';

  static CobroDiagnosticoComparacion comparar({
    required CobroDiagnosticoReporte local,
    required CobroDiagnosticoReporte remoto,
  }) {
    final localClaves = {
      for (final i in local.inconsistencias) clave(i),
    };
    final remotoClaves = {
      for (final i in remoto.inconsistencias) clave(i),
    };

    return CobroDiagnosticoComparacion(
      local: local,
      remoto: remoto,
      clavesSoloLocal: localClaves.difference(remotoClaves),
      clavesSoloRemoto: remotoClaves.difference(localClaves),
      clavesEnAmbos: localClaves.intersection(remotoClaves),
    );
  }
}
