import '../core/sport_type.dart';
import '../models/detalle_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/mi_convocatoria.dart';
import 'player_invite_response.dart';

/// Arquetipo deportivo privado (sin finanzas ni rankings).
enum PlayerSportArchetype {
  constante,
  responsable,
  veterano,
  explorador,
  activo,
  nuevo,
}

class PlayerProfilePrideData {
  final PlayerSportArchetype archetype;
  final int rachaSemanasConsecutivas;
  final int semanasActivas;
  final int porcentajeAsistencia;
  final int encuentrosTotal;
  final List<SportType> deportesJugados;
  final List<int> actividadMensual;

  const PlayerProfilePrideData({
    required this.archetype,
    required this.rachaSemanasConsecutivas,
    required this.semanasActivas,
    required this.porcentajeAsistencia,
    required this.encuentrosTotal,
    required this.deportesJugados,
    required this.actividadMensual,
  });
}

PlayerProfilePrideData buildPlayerProfilePride({
  required EstadisticasJugador? stats,
  required MisInvitacionesResumen invitaciones,
  required List<DetallePartido> partidos,
  required List<MiConvocatoria> convocatorias,
}) {
  final fechas = _fechasActividad(partidos, convocatorias);
  final semanasActivas = _contarSemanasUnicas(fechas);
  final racha = _rachaSemanasConsecutivas(fechas);
  final deportes = _deportesDesdeActividad(partidos, convocatorias);
  final encuentros = stats?.partidosJugados ?? partidos.length;
  final asistencia = _porcentajeAsistencia(invitaciones, stats);
  final actividadMensual = _actividadPorMes(fechas, meses: 12);
  final archetype = _resolverArquetipo(
    partidos: encuentros,
    ultimos90: stats?.partidosUltimos90Dias ?? 0,
    invitaciones: invitaciones,
    rachaSemanas: racha,
    semanasActivas: semanasActivas,
    deportesCount: deportes.length,
  );

  return PlayerProfilePrideData(
    archetype: archetype,
    rachaSemanasConsecutivas: racha,
    semanasActivas: semanasActivas,
    porcentajeAsistencia: asistencia,
    encuentrosTotal: encuentros,
    deportesJugados: deportes,
    actividadMensual: actividadMensual,
  );
}

List<DateTime> _fechasActividad(
  List<DetallePartido> partidos,
  List<MiConvocatoria> convocatorias,
) {
  return [
    ...partidos.map((p) => p.fechaPartido).whereType<DateTime>(),
    ...convocatorias
        .where((c) => c.estaConfirmado || c.esProximo)
        .map((c) => c.partido.fecha),
  ];
}

int _contarSemanasUnicas(List<DateTime> fechas) {
  if (fechas.isEmpty) return 0;
  final semanas = fechas.map(_inicioSemana).toSet();
  return semanas.length;
}

DateTime _inicioSemana(DateTime f) {
  final lunes = f.subtract(Duration(days: f.weekday - 1));
  return DateTime(lunes.year, lunes.month, lunes.day);
}

int _rachaSemanasConsecutivas(List<DateTime> fechas) {
  if (fechas.isEmpty) return 0;
  final semanas = fechas.map(_inicioSemana).toSet().toList()
    ..sort((a, b) => b.compareTo(a));

  var racha = 1;
  for (var i = 1; i < semanas.length; i++) {
    final diff = semanas[i - 1].difference(semanas[i]).inDays;
    if (diff == 7) {
      racha++;
    } else {
      break;
    }
  }
  return racha;
}

int _porcentajeAsistencia(
  MisInvitacionesResumen invitaciones,
  EstadisticasJugador? stats,
) {
  if (invitaciones.recibidas >= 1) {
    return invitaciones.porcentajeRespuesta.round().clamp(0, 100);
  }
  final jugados = stats?.partidosJugados ?? 0;
  final confirmadas = stats?.convocatoriasConfirmadas ?? 0;
  if (jugados == 0 && confirmadas == 0) return 0;
  if (jugados == 0) return 100;
  final pct = (confirmadas / jugados) * 100;
  return pct.round().clamp(0, 100);
}

List<SportType> _deportesDesdeActividad(
  List<DetallePartido> partidos,
  List<MiConvocatoria> convocatorias,
) {
  final set = <SportType>{};
  for (final p in partidos) {
    if (p.sportType != null) set.add(p.sportType!);
  }
  for (final c in convocatorias) {
    set.add(c.partido.sportType);
  }
  final list = set.toList();
  list.sort((a, b) => a.labelEs.compareTo(b.labelEs));
  return list;
}

List<int> _actividadPorMes(List<DateTime> fechas, {int meses = 12}) {
  final now = DateTime.now();
  final counts = List<int>.filled(meses, 0);
  for (final f in fechas) {
    for (var i = 0; i < meses; i++) {
      final anchor = DateTime(now.year, now.month - (meses - 1 - i), 1);
      if (f.year == anchor.year && f.month == anchor.month) {
        counts[i]++;
      }
    }
  }
  return counts;
}

PlayerSportArchetype _resolverArquetipo({
  required int partidos,
  required int ultimos90,
  required MisInvitacionesResumen invitaciones,
  required int rachaSemanas,
  required int semanasActivas,
  required int deportesCount,
}) {
  if (partidos == 0 && invitaciones.recibidas == 0) {
    return PlayerSportArchetype.nuevo;
  }
  if (rachaSemanas >= 3 || (semanasActivas >= 5 && partidos >= 3)) {
    return PlayerSportArchetype.constante;
  }
  if (invitaciones.recibidas >= 3 &&
      invitaciones.porcentajeRespuesta >= 75) {
    return PlayerSportArchetype.responsable;
  }
  if (partidos >= 15) {
    return PlayerSportArchetype.veterano;
  }
  if (deportesCount >= 2) {
    return PlayerSportArchetype.explorador;
  }
  if (partidos >= 3 || ultimos90 >= 2) {
    return PlayerSportArchetype.activo;
  }
  return PlayerSportArchetype.nuevo;
}

String archetypeTitleKey(PlayerSportArchetype a) => switch (a) {
      PlayerSportArchetype.constante => 'playerArchetypeConstantTitle',
      PlayerSportArchetype.responsable => 'playerArchetypeReliableTitle',
      PlayerSportArchetype.veterano => 'playerArchetypeVeteranTitle',
      PlayerSportArchetype.explorador => 'playerArchetypeExplorerTitle',
      PlayerSportArchetype.activo => 'playerArchetypeActiveTitle',
      PlayerSportArchetype.nuevo => 'playerArchetypeNewTitle',
    };

String archetypeBodyKey(PlayerSportArchetype a) => switch (a) {
      PlayerSportArchetype.constante => 'playerArchetypeConstantBody',
      PlayerSportArchetype.responsable => 'playerArchetypeReliableBody',
      PlayerSportArchetype.veterano => 'playerArchetypeVeteranBody',
      PlayerSportArchetype.explorador => 'playerArchetypeExplorerBody',
      PlayerSportArchetype.activo => 'playerArchetypeActiveBody',
      PlayerSportArchetype.nuevo => 'playerArchetypeNewBody',
    };

String archetypeHeadlineKey(PlayerSportArchetype a) => switch (a) {
      PlayerSportArchetype.constante => 'playerArchetypeConstantHeadline',
      PlayerSportArchetype.responsable => 'playerArchetypeReliableHeadline',
      PlayerSportArchetype.veterano => 'playerArchetypeVeteranHeadline',
      PlayerSportArchetype.explorador => 'playerArchetypeExplorerHeadline',
      PlayerSportArchetype.activo => 'playerArchetypeActiveHeadline',
      PlayerSportArchetype.nuevo => 'playerArchetypeNewHeadline',
    };
