import '../core/sport_type.dart';
import '../models/detalle_partido.dart';
import '../models/mi_convocatoria.dart';
import 'player_invite_response.dart';

/// Insignias de comportamiento (privadas, sin rankings).
enum PlayerBehaviorBadge {
  alwaysPresent,
  explorer,
  earlyBird,
  nightOwl,
}

class PlayerBehaviorBadgeView {
  final PlayerBehaviorBadge id;
  final bool unlocked;
  final String emoji;

  const PlayerBehaviorBadgeView({
    required this.id,
    required this.unlocked,
    required this.emoji,
  });
}

List<PlayerBehaviorBadgeView> buildPlayerBehaviorBadges({
  required List<DetallePartido> partidos,
  required List<MiConvocatoria> convocatorias,
  required MisInvitacionesResumen invitaciones,
}) {
  final fechas = _fechasEvaluacion(partidos, convocatorias);
  final deportes = _deportes(partidos, convocatorias);
  final recintos = _recintosUnicos(partidos, convocatorias);

  final alwaysPresent = _tieneSiemprePresente(partidos, invitaciones);
  final explorer = deportes.length >= 2 || recintos.length >= 2;
  final earlyBird = fechas.any((f) => f.hour < 9);
  final nightOwl = fechas.any((f) => f.hour >= 20);

  return [
    PlayerBehaviorBadgeView(
      id: PlayerBehaviorBadge.alwaysPresent,
      unlocked: alwaysPresent,
      emoji: '🏆',
    ),
    PlayerBehaviorBadgeView(
      id: PlayerBehaviorBadge.explorer,
      unlocked: explorer,
      emoji: '🧭',
    ),
    PlayerBehaviorBadgeView(
      id: PlayerBehaviorBadge.earlyBird,
      unlocked: earlyBird,
      emoji: '🌅',
    ),
    PlayerBehaviorBadgeView(
      id: PlayerBehaviorBadge.nightOwl,
      unlocked: nightOwl,
      emoji: '🌙',
    ),
  ];
}

bool _tieneSiemprePresente(
  List<DetallePartido> partidos,
  MisInvitacionesResumen invitaciones,
) {
  if (invitaciones.confirmadas < 2) return false;
  final rechazos = invitaciones.respondidas - invitaciones.confirmadas;
  if (rechazos > 0) return false;
  if (partidos.isEmpty) return invitaciones.confirmadas >= 2;
  return partidos.every((p) => p.asistio);
}

List<DateTime> _fechasEvaluacion(
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

List<SportType> _deportes(
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
  return set.toList();
}

List<String> _recintosUnicos(
  List<DetallePartido> partidos,
  List<MiConvocatoria> convocatorias,
) {
  final set = <String>{};
  for (final p in partidos) {
    final r = p.recintoPartido?.trim();
    if (r != null && r.isNotEmpty) set.add(r.toLowerCase());
  }
  for (final c in convocatorias) {
    final r = c.partido.recinto?.trim();
    if (r != null && r.isNotEmpty) set.add(r.toLowerCase());
  }
  return set.toList();
}

String badgeTitleKey(PlayerBehaviorBadge id) => switch (id) {
      PlayerBehaviorBadge.alwaysPresent => 'playerBadgeAlwaysPresentTitle',
      PlayerBehaviorBadge.explorer => 'playerBadgeExplorerTitle',
      PlayerBehaviorBadge.earlyBird => 'playerBadgeEarlyBirdTitle',
      PlayerBehaviorBadge.nightOwl => 'playerBadgeNightOwlTitle',
    };

String badgeBodyKey(PlayerBehaviorBadge id) => switch (id) {
      PlayerBehaviorBadge.alwaysPresent => 'playerBadgeAlwaysPresentBody',
      PlayerBehaviorBadge.explorer => 'playerBadgeExplorerBody',
      PlayerBehaviorBadge.earlyBird => 'playerBadgeEarlyBirdBody',
      PlayerBehaviorBadge.nightOwl => 'playerBadgeNightOwlBody',
    };
