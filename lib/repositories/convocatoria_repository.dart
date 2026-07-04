import '../database/database_helper.dart';
import '../models/convocatoria_jugador.dart';
import '../core/sport_type.dart';
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
      SELECT cj.*, j.nombre, j.activo, j.saldo_acumulado, j.email, j.telefono, j.created_at
      FROM convocatoria_jugadores cj
      JOIN jugadores j ON j.id = cj.jugador_id
      WHERE cj.partido_id = ?
      ORDER BY cj.es_suplente ASC, cj.orden_espera ASC, j.nombre COLLATE NOCASE ASC
    ''', [partidoId]);

    final jugadores = convRows.map((row) {
      final jugador = Jugador.fromMap({
        'id': row['jugador_id'],
        'nombre': row['nombre'],
        'activo': row['activo'],
        'saldo_acumulado': row['saldo_acumulado'],
        'email': row['email'],
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
    int horasLimiteRespuesta = 24,
    required List<ConvocatoriaJugadorInput> jugadores,
    SportType? sportType,
  }) async {
    final sport = sportType ?? SportType.padel;
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
        'horas_limite_respuesta': horasLimiteRespuesta,
        'sport_type': sport.dbValue,
        'created_at': DateTime.now().toIso8601String(),
      });

      for (final input in jugadores) {
        final jugadorId = int.parse(input.jugadorId);
        await txn.insert(
          'convocatoria_jugadores',
          _rowForInput(
            partidoId: partidoId,
            jugadorId: jugadorId,
            input: input,
            horasLimite: horasLimiteRespuesta,
          ),
        );
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
    required int horasLimiteRespuesta,
    required List<ConvocatoriaJugadorInput> jugadores,
    SportType? sportType,
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
          'horas_limite_respuesta': horasLimiteRespuesta,
          if (sportType != null) 'sport_type': sportType.dbValue,
        },
        where: 'id = ?',
        whereArgs: [partidoId],
      );

      await txn.delete(
        'convocatoria_jugadores',
        where: 'partido_id = ?',
        whereArgs: [partidoId],
      );

      for (final input in jugadores) {
        final jugadorId = int.parse(input.jugadorId);
        await txn.insert(
          'convocatoria_jugadores',
          _rowForInput(
            partidoId: partidoId,
            jugadorId: jugadorId,
            input: input,
            horasLimite: horasLimiteRespuesta,
          ),
        );
      }
    });
  }

  Map<String, dynamic> _rowForInput({
    required int partidoId,
    required int jugadorId,
    required ConvocatoriaJugadorInput input,
    required int horasLimite,
    bool conTiempoLimite = false,
  }) {
    String? tiempoLimite;
    if (conTiempoLimite &&
        !input.esSuplente &&
        input.estado == EstadoConfirmacion.invitado) {
      tiempoLimite = DateTime.now()
          .add(Duration(hours: horasLimite))
          .toIso8601String();
    }
    return {
      'partido_id': partidoId,
      'jugador_id': jugadorId,
      'estado_confirmacion': input.estado.dbValue,
      'es_suplente': input.esSuplente ? 1 : 0,
      'orden_espera': input.ordenEspera,
      'tiempo_limite': tiempoLimite,
      'notificado_vencimiento': 0,
      'recordatorio_plazo_enviado': 0,
    };
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

  Future<void> marcarNoRespondio({
    required int partidoId,
    required int jugadorId,
    bool notificadoVencimiento = false,
  }) async {
    final db = await _db.database;
    await db.update(
      'convocatoria_jugadores',
      {
        'estado_confirmacion': EstadoConfirmacion.noRespondio.dbValue,
        'notificado_vencimiento': notificadoVencimiento ? 1 : 0,
      },
      where: 'partido_id = ? AND jugador_id = ?',
      whereArgs: [partidoId, jugadorId],
    );
  }

  Future<void> marcarRecordatorioPlazoEnviado({
    required int partidoId,
    required int jugadorId,
  }) async {
    final db = await _db.database;
    try {
      await db.update(
        'convocatoria_jugadores',
        {'recordatorio_plazo_enviado': 1},
        where: 'partido_id = ? AND jugador_id = ?',
        whereArgs: [partidoId, jugadorId],
      );
    } catch (_) {}
  }

  Future<Jugador?> promoverSiguienteSuplente(int partidoId) async {
    final conv = await getCompleta(partidoId);
    if (conv == null) return null;
    if (conv.confirmados >= conv.partido.cuposMax) return null;
    if (conv.suplentes.isEmpty) return null;

    final suplente = conv.suplentes.first;
    final jugadorId = suplente.jugador.id;
    if (jugadorId == null) return null;

    final limite = DateTime.now().add(
      Duration(hours: conv.partido.horasLimiteRespuesta),
    );
    final db = await _db.database;
    await db.update(
      'convocatoria_jugadores',
      {
        'es_suplente': 0,
        'orden_espera': null,
        'estado_confirmacion': EstadoConfirmacion.invitado.dbValue,
        'tiempo_limite': limite.toIso8601String(),
        'notificado_vencimiento': 0,
        'recordatorio_plazo_enviado': 0,
      },
      where: 'partido_id = ? AND jugador_id = ?',
      whereArgs: [partidoId, jugadorId],
    );
    return suplente.jugador;
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
      where:
          'partido_id = ? AND es_suplente = 0 AND estado_confirmacion = ?',
      whereArgs: [partidoId, EstadoConfirmacion.confirmado.dbValue],
    );
    return rows.map((r) => r['jugador_id'] as int).toList();
  }

  Future<void> activarTiemposLimiteConvocatoria({
    required int partidoId,
    required int horasLimite,
  }) async {
    final limite =
        DateTime.now().add(Duration(hours: horasLimite)).toIso8601String();
    final db = await _db.database;
    await db.update(
      'convocatoria_jugadores',
      {'tiempo_limite': limite},
      where:
          'partido_id = ? AND es_suplente = 0 AND estado_confirmacion = ?',
      whereArgs: [partidoId, EstadoConfirmacion.invitado.dbValue],
    );
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
