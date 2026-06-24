import '../database/database_helper.dart';
import '../models/jugador.dart';

class JugadorRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Jugador>> getAll({bool? soloActivos}) async {
    final db = await _db.database;
    String? where;
    List<Object?>? whereArgs;

    if (soloActivos == true) {
      where = 'activo = ?';
      whereArgs = [1];
    }

    final rows = await db.query(
      'jugadores',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'nombre COLLATE NOCASE ASC',
    );
    return rows.map(Jugador.fromMap).toList();
  }

  Future<Jugador?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('jugadores', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Jugador.fromMap(rows.first);
  }

  Future<int> insert(Jugador jugador) async {
    final db = await _db.database;
    return db.insert('jugadores', jugador.toMap());
  }

  Future<int> update(Jugador jugador) async {
    final db = await _db.database;
    return db.update(
      'jugadores',
      jugador.toMap(),
      where: 'id = ?',
      whereArgs: [jugador.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('jugadores', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSaldo(int jugadorId, double nuevoSaldo) async {
    final db = await _db.database;
    await db.update(
      'jugadores',
      {'saldo_acumulado': nuevoSaldo},
      where: 'id = ?',
      whereArgs: [jugadorId],
    );
  }
}
