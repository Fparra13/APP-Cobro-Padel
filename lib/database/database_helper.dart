import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'padel_cobro.db');

    return openDatabase(
      path,
      version: 6,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE jugadores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        activo INTEGER NOT NULL DEFAULT 1,
        saldo_acumulado REAL NOT NULL DEFAULT 0,
        telefono TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE partidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        costo_cancha REAL NOT NULL DEFAULT 0,
        costo_pelotas REAL NOT NULL DEFAULT 0,
        recinto TEXT,
        notas TEXT,
        comprobante_cancha TEXT,
        comprobante_pelotas TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE detalles_partido (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        partido_id INTEGER NOT NULL,
        jugador_id INTEGER NOT NULL,
        asistio INTEGER NOT NULL DEFAULT 1,
        prorrateo_fijo REAL NOT NULL DEFAULT 0,
        total_variables REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        pagado INTEGER NOT NULL DEFAULT 0,
        fecha_pago TEXT,
        monto_pagado REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (partido_id) REFERENCES partidos(id) ON DELETE CASCADE,
        FOREIGN KEY (jugador_id) REFERENCES jugadores(id) ON DELETE RESTRICT,
        UNIQUE(partido_id, jugador_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE costos_variables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        partido_id INTEGER NOT NULL,
        concepto TEXT NOT NULL,
        monto_total REAL NOT NULL,
        comprobante_path TEXT,
        FOREIGN KEY (partido_id) REFERENCES partidos(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE asignaciones_costo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        costo_variable_id INTEGER NOT NULL,
        jugador_id INTEGER NOT NULL,
        monto REAL NOT NULL,
        FOREIGN KEY (costo_variable_id) REFERENCES costos_variables(id) ON DELETE CASCADE,
        FOREIGN KEY (jugador_id) REFERENCES jugadores(id) ON DELETE RESTRICT,
        UNIQUE(costo_variable_id, jugador_id)
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
        concepto TEXT NOT NULL,
        FOREIGN KEY (jugador_id) REFERENCES jugadores(id) ON DELETE RESTRICT,
        FOREIGN KEY (partido_id) REFERENCES partidos(id) ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_detalles_partido ON detalles_partido(partido_id)',
    );
    await db.execute(
      'CREATE INDEX idx_saldos_jugador ON saldos_historicos(jugador_id)',
    );
    await db.execute(
      'CREATE INDEX idx_costos_variables_partido ON costos_variables(partido_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE jugadores ADD COLUMN telefono TEXT');
      await db.execute(
        'ALTER TABLE detalles_partido ADD COLUMN fecha_pago TEXT',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE detalles_partido ADD COLUMN monto_pagado REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE partidos ADD COLUMN recinto TEXT');
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE detalles_partido ADD COLUMN comprobante_path TEXT',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE partidos ADD COLUMN comprobante_cancha TEXT',
      );
      await db.execute(
        'ALTER TABLE partidos ADD COLUMN comprobante_pelotas TEXT',
      );
      await db.execute(
        'ALTER TABLE costos_variables ADD COLUMN comprobante_path TEXT',
      );
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }

  Future<void> resetDatabase() async {
    await close();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'padel_cobro.db');
    await deleteDatabase(path);
    _database = await _initDatabase();
  }
}
