import '../database/database_helper.dart';
import '../models/saldo_historico.dart';

class SaldoRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<SaldoHistorico>> getByPartido(int partidoId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT sh.*, j.nombre AS nombre_jugador
      FROM saldos_historicos sh
      JOIN jugadores j ON j.id = sh.jugador_id
      WHERE sh.partido_id = ?
      ORDER BY j.nombre COLLATE NOCASE ASC
    ''', [partidoId]);
    return rows.map(SaldoHistorico.fromMap).toList();
  }

  Future<List<SaldoHistorico>> getByJugador(int jugadorId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT sh.*, j.nombre AS nombre_jugador
      FROM saldos_historicos sh
      JOIN jugadores j ON j.id = sh.jugador_id
      WHERE sh.jugador_id = ?
      ORDER BY sh.fecha DESC
    ''', [jugadorId]);
    return rows.map(SaldoHistorico.fromMap).toList();
  }

  Future<List<SaldoHistorico>> getAll() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT sh.*, j.nombre AS nombre_jugador
      FROM saldos_historicos sh
      JOIN jugadores j ON j.id = sh.jugador_id
      ORDER BY sh.fecha DESC
      LIMIT 100
    ''');
    return rows.map(SaldoHistorico.fromMap).toList();
  }

  Future<int> insert(SaldoHistorico saldo) async {
    final db = await _db.database;
    return db.insert('saldos_historicos', saldo.toMap());
  }
}
