import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/diagnostics/sqlite_cobro_diagnostico.dart';
import 'package:matchpay/domain/cobro_diagnostico.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('SqliteCobroDiagnostico detecta inconsistencias en BD en memoria', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 13,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE jugadores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nombre TEXT NOT NULL,
            saldo_acumulado REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE partidos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fecha TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE detalles_partido (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            partido_id INTEGER NOT NULL,
            jugador_id INTEGER NOT NULL,
            asistio INTEGER NOT NULL DEFAULT 1,
            total REAL NOT NULL DEFAULT 0,
            monto_pagado REAL NOT NULL DEFAULT 0,
            pagado INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE saldos_historicos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jugador_id INTEGER NOT NULL,
            partido_id INTEGER,
            saldo_anterior REAL NOT NULL,
            cargo_partido REAL NOT NULL DEFAULT 0,
            abono REAL NOT NULL DEFAULT 0,
            saldo_nuevo REAL NOT NULL,
            fecha TEXT NOT NULL,
            concepto TEXT NOT NULL
          )
        ''');
      },
    );

    await db.insert('jugadores', {'id': 1, 'nombre': 'Ana', 'saldo_acumulado': 5000});
    await db.insert('partidos', {'id': 10, 'fecha': '2025-01-01T12:00:00.000'});
    await db.insert('detalles_partido', {
      'id': 100,
      'partido_id': 10,
      'jugador_id': 1,
      'asistio': 1,
      'total': 8000,
      'monto_pagado': 0,
      'pagado': 0,
    });

    final reporte = await SqliteCobroDiagnostico.analizarBaseLocal(database: db);

    expect(
      reporte.conteoPorTipo[
          CobroInconsistenciaTipo.detalleSinSnapshotHistorico],
      1,
    );
    expect(
      reporte.conteoPorTipo[CobroInconsistenciaTipo.partidoSinHistorial],
      1,
    );
    expect(
      reporte.conteoPorTipo[
          CobroInconsistenciaTipo.saldoAcumuladoDifiereHistorial],
      1,
    );

    await db.close();
  });
}
