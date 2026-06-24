import '../database/database_helper.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../models/partido.dart';

class ConvocatoriaRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<ConvocatoriaCompleta>> getActivas() async {
    final db = await _db.database;
    final rows = await db.query(
      'partidos',
      where: 'estado IN (?, ?)',
      whereArgs: [
        EstadoPartido.organizando.dbValue,
        EstadoPartido.confirmado.dbValue,
      ],
      orderBy: 'fecha ASC',
    );

    final result = <ConvocatoriaCompleta>[];
    for (final row in rows) {
      final conv = await getCompleta(row['id'] as int);
      if (conv != null) result.add(conv);
    }
    return result;
  }

  Future<List<ConvocatoriaCompleta>> getEnEspera() async {
    return _getPorEstado(EstadoPartido.organizando);
  }

  Future<List<ConvocatoriaCompleta>> getConfirmadas() async {
    return _getPorEstado(EstadoPartido.confirmado);
  }

  Future<List<ConvocatoriaCompleta>> _getPorEstado(EstadoPartido estado) async {
    final db = await _db.database;
    final rows = await db.query(
      'partidos',
      where: 'estado = ?',
      whereArgs: [estado.dbValue],
      orderBy: 'fecha ASC',
    );

    final result = <ConvocatoriaCompleta>[];
    for (final row in rows) {
      final conv = await getCompleta(row['id'] as int);
      if (conv != null) result.add(conv);
    }
    return result;
  }

  Future<ConvocatoriaCompleta?> getCompleta(int partidoId) async {
    final db = await _db.database;
    final partidoRows = await db.query(
      'partidos',
      where: 'id = ?',
      whereArgs: [partidoId],
    );
    if (partidoRows.isEmpty) return null;

    final partido = Partido.fromMap(partidoRows.first);
    if (!partido.esConvocatoriaPendiente) return null;

    final convRows = await db.rawQuery('''
      SELECT cj.*, j.nombre, j.activo, j.saldo_acumulado, j.telefono, j.created_at
      FROM convocatoria_jugadores cj
      JOIN jugadores j ON j.id = cj.jugador_id
      WHERE cj.partido_id = ?
      ORDER BY j.nombre COLLATE NOCASE ASC
    ''', [partidoId]);

    final jugadores = convRows.map((row) {
      final jugador = Jugador.fromMap({
        'id': row['jugador_id'],
        'nombre': row['nombre'],
        'activo': row['activo'],
        'saldo_acumulado': row['saldo_acumulado'],
        'telefono': row['telefono'],
        'created_at': row['created_at'],
      });
      return ConvocatoriaJugadorEntry.fromMap(row, jugador);
    }).toList();

    return ConvocatoriaCompleta(partido: partido, jugadores: jugadores);
  }

  Future<int> crear({
    required DateTime fecha,
    String? recinto,
    String? notas,
    int cuposMax = 4,
    required List<int> jugadoresInvitados,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final partidoId = await txn.insert('partidos', {
        'fecha': fecha.toIso8601String(),
        'costo_cancha': 0,
        'costo_pelotas': 0,
        'recinto': recinto,
        'notas': notas,
        'estado': EstadoPartido.organizando.dbValue,
        'cupos_max': cuposMax,
        'created_at': DateTime.now().toIso8601String(),
      });

      for (final jugadorId in jugadoresInvitados.toSet()) {
        await txn.insert('convocatoria_jugadores', {
          'partido_id': partidoId,
          'jugador_id': jugadorId,
          'estado_confirmacion': EstadoConfirmacion.invitado.dbValue,
        });
      }

      return partidoId;
    });
  }

  Future<void> actualizar({
    required int partidoId,
    required DateTime fecha,
    String? recinto,
    String? notas,
    required int cuposMax,
    required List<int> jugadoresInvitados,
    required Map<int, EstadoConfirmacion> estados,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'partidos',
        {
          'fecha': fecha.toIso8601String(),
          'recinto': recinto,
          'notas': notas,
          'cupos_max': cuposMax,
        },
        where: 'id = ?',
        whereArgs: [partidoId],
      );

      await txn.delete(
        'convocatoria_jugadores',
        where: 'partido_id = ?',
        whereArgs: [partidoId],
      );

      for (final jugadorId in jugadoresInvitados.toSet()) {
        await txn.insert('convocatoria_jugadores', {
          'partido_id': partidoId,
          'jugador_id': jugadorId,
          'estado_confirmacion':
              (estados[jugadorId] ?? EstadoConfirmacion.invitado).dbValue,
        });
      }
    });
  }

  Future<void> actualizarConfirmacion({
    required int partidoId,
    required int jugadorId,
    required EstadoConfirmacion estado,
  }) async {
    final db = await _db.database;
    await db.update(
      'convocatoria_jugadores',
      {'estado_confirmacion': estado.dbValue},
      where: 'partido_id = ? AND jugador_id = ?',
      whereArgs: [partidoId, jugadorId],
    );
  }

  Future<void> aplicarConfirmaciones({
    required int partidoId,
    required Map<int, EstadoConfirmacion> cambios,
  }) async {
    for (final entry in cambios.entries) {
      await actualizarConfirmacion(
        partidoId: partidoId,
        jugadorId: entry.key,
        estado: entry.value,
      );
    }
  }

  Future<List<int>> getConfirmadosIds(int partidoId) async {
    final db = await _db.database;
    final rows = await db.query(
      'convocatoria_jugadores',
      columns: ['jugador_id'],
      where: 'partido_id = ? AND estado_confirmacion = ?',
      whereArgs: [partidoId, EstadoConfirmacion.confirmado.dbValue],
    );
    return rows.map((r) => r['jugador_id'] as int).toList();
  }

  Future<void> marcarConfirmado(int partidoId) async {
    final db = await _db.database;
    await db.update(
      'partidos',
      {'estado': EstadoPartido.confirmado.dbValue},
      where: 'id = ?',
      whereArgs: [partidoId],
    );
  }

  Future<void> eliminar(int partidoId) async {
    final db = await _db.database;
    await db.delete('partidos', where: 'id = ?', whereArgs: [partidoId]);
  }
}
