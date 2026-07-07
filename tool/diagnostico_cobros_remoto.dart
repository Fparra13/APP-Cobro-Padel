import 'dart:io';

import 'package:matchpay/diagnostics/cobro_diagnostico_comparador.dart';
import 'package:matchpay/diagnostics/sqlite_cobro_diagnostico.dart';
import 'package:matchpay/diagnostics/supabase_cobro_diagnostico.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Diagnóstico remoto Supabase y comparación opcional con SQLite local.
///
/// Requiere:
///   --dart-define=SUPABASE_SERVICE_ROLE_KEY=...
///
/// Ejecutar:
///   flutter test tool/diagnostico_cobros_remoto.dart
Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  stdout.writeln('=== Diagnóstico Supabase (solo lectura) ===\n');
  final remoto = await SupabaseCobroDiagnostico.analizar();
  stdout.writeln(remoto.resumenTexto());

  stdout.writeln('=== Diagnóstico SQLite local ===\n');
  final local = await SqliteCobroDiagnostico.analizarBaseLocal();
  stdout.writeln(local.resumenTexto());

  stdout.writeln('=== Comparación ===\n');
  final cmp = CobroDiagnosticoComparador.comparar(local: local, remoto: remoto);
  stdout.writeln(cmp.resumenTexto());

  final exitCode = remoto.tieneProblemas || local.tieneProblemas ? 1 : 0;
  exit(exitCode);
}
