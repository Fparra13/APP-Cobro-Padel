import 'dart:io';

import 'package:matchpay/diagnostics/sqlite_cobro_diagnostico.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Diagnóstico SSOT de cobros sobre la base SQLite local del dispositivo/emulador.
///
/// Requiere FFI (no funciona con `dart run` puro sobre sqflite móvil).
/// Ejecutar: flutter test tool/diagnostico_cobros.dart
///
/// O desde tests: `flutter test test/cobro_diagnostico_test.dart`
void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final reporte = await SqliteCobroDiagnostico.analizarBaseLocal();
  stdout.writeln(reporte.resumenTexto());

  if (!reporte.tieneProblemas) {
    stdout.writeln('Sin inconsistencias detectadas.');
    exit(0);
  }
  exit(1);
}
