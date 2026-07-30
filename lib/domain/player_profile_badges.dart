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
  firstStep,
  seasonedPlayer,
  legend,
  streakKeeper,
  unstoppable,
  consistent,
  yearRound,
  weekendWarrior,
  afterWork,
  allDayAthlete,
  teamPlayer,
  communityBuilder,
  familiarFaces,
  allRounder,
  sportCollector,
  venueExplorer,
  traveler,
  winterSpirit,
  summerSpirit,
  rainOrShine,
  earlySeason,
  milestone50,
  milestone250,
  anniversary,
  fiveYears,
}

/// Rareza de presentación (vitrinas / filtros futuros).
enum BadgeRarity {
  common,
  uncommon,
  rare,
  epic,
  legendary,
}

/// Familia temática de la insignia.
enum BadgeCategory {
  participation,
  consistency,
  exploration,
  community,
  milestones,
  time,
}

/// Si la insignia se muestra en colección antes de desbloquearse.
enum BadgeVisibility {
  /// Siempre listada (bloqueada o no).
  visible,
  /// Solo aparece cuando [PlayerBehaviorBadgeView.unlocked] es true.
  hiddenUntilUnlocked,
}

/// Criterios de ordenación para vitrinas / perfil (UI futura).
enum BadgeSortBy {
  displayOrder,
  rarity,
  category,
  level,
  unlockedFirst,
}

/// Definición canónica de una insignia: presentación + niveles (si aplica).
///
/// Agregar una insignia = un valor en [PlayerBehaviorBadge] + una entrada en
/// [playerBadgeCatalog]. El desbloqueo sigue viviendo en
/// [buildPlayerBehaviorBadges].
class PlayerBadgeDefinition {
  final PlayerBehaviorBadge id;
  final String emoji;
  final String titleKey;
  final String bodyKey;
  final BadgeRarity rarity;
  final BadgeCategory category;
  final BadgeVisibility visibility;
  final int displayOrder;
  /// Umbrales de nivel (índice 0 = nivel 1). `null` = insignia binaria.
  final List<int>? levelThresholds;

  const PlayerBadgeDefinition({
    required this.id,
    required this.emoji,
    required this.titleKey,
    required this.bodyKey,
    required this.rarity,
    required this.category,
    required this.visibility,
    required this.displayOrder,
    this.levelThresholds,
  });

  bool get hasLevels =>
      levelThresholds != null && levelThresholds!.isNotEmpty;
}

/// Catálogo único: emoji, l10n, rareza, categoría, visibilidad, orden y niveles.
const Map<PlayerBehaviorBadge, PlayerBadgeDefinition> playerBadgeCatalog = {
  PlayerBehaviorBadge.firstStep: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.firstStep,
    emoji: '👟',
    titleKey: 'playerBadgeFirstStepTitle',
    bodyKey: 'playerBadgeFirstStepBody',
    rarity: BadgeRarity.common,
    category: BadgeCategory.participation,
    visibility: BadgeVisibility.visible,
    displayOrder: 1,
  ),
  PlayerBehaviorBadge.milestone50: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.milestone50,
    emoji: '🎉',
    titleKey: 'playerBadgeMilestone50Title',
    bodyKey: 'playerBadgeMilestone50Body',
    rarity: BadgeRarity.rare,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.visible,
    displayOrder: 2,
  ),
  PlayerBehaviorBadge.seasonedPlayer: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.seasonedPlayer,
    emoji: '🏅',
    titleKey: 'playerBadgeSeasonedPlayerTitle',
    bodyKey: 'playerBadgeSeasonedPlayerBody',
    rarity: BadgeRarity.rare,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.visible,
    displayOrder: 3,
    levelThresholds: [25, 50, 100, 250, 500],
  ),
  PlayerBehaviorBadge.milestone250: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.milestone250,
    emoji: '🥇',
    titleKey: 'playerBadgeMilestone250Title',
    bodyKey: 'playerBadgeMilestone250Body',
    rarity: BadgeRarity.epic,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 4,
  ),
  PlayerBehaviorBadge.legend: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.legend,
    emoji: '👑',
    titleKey: 'playerBadgeLegendTitle',
    bodyKey: 'playerBadgeLegendBody',
    rarity: BadgeRarity.legendary,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 5,
  ),
  PlayerBehaviorBadge.streakKeeper: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.streakKeeper,
    emoji: '🔥',
    titleKey: 'playerBadgeStreakKeeperTitle',
    bodyKey: 'playerBadgeStreakKeeperBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.consistency,
    visibility: BadgeVisibility.visible,
    displayOrder: 6,
    levelThresholds: [4, 8, 16, 26, 52],
  ),
  PlayerBehaviorBadge.unstoppable: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.unstoppable,
    emoji: '💪',
    titleKey: 'playerBadgeUnstoppableTitle',
    bodyKey: 'playerBadgeUnstoppableBody',
    rarity: BadgeRarity.epic,
    category: BadgeCategory.consistency,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 7,
  ),
  PlayerBehaviorBadge.consistent: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.consistent,
    emoji: '⭐',
    titleKey: 'playerBadgeConsistentTitle',
    bodyKey: 'playerBadgeConsistentBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.consistency,
    visibility: BadgeVisibility.visible,
    displayOrder: 8,
  ),
  PlayerBehaviorBadge.alwaysPresent: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.alwaysPresent,
    emoji: '🏆',
    titleKey: 'playerBadgeAlwaysPresentTitle',
    bodyKey: 'playerBadgeAlwaysPresentBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.consistency,
    visibility: BadgeVisibility.visible,
    displayOrder: 9,
  ),
  PlayerBehaviorBadge.explorer: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.explorer,
    emoji: '🧭',
    titleKey: 'playerBadgeExplorerTitle',
    bodyKey: 'playerBadgeExplorerBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.exploration,
    visibility: BadgeVisibility.visible,
    displayOrder: 10,
  ),
  PlayerBehaviorBadge.allRounder: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.allRounder,
    emoji: '🌍',
    titleKey: 'playerBadgeAllRounderTitle',
    bodyKey: 'playerBadgeAllRounderBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.exploration,
    visibility: BadgeVisibility.visible,
    displayOrder: 11,
    levelThresholds: [2, 4, 6, 8, 10],
  ),
  PlayerBehaviorBadge.sportCollector: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.sportCollector,
    emoji: '🏆',
    titleKey: 'playerBadgeSportCollectorTitle',
    bodyKey: 'playerBadgeSportCollectorBody',
    rarity: BadgeRarity.epic,
    category: BadgeCategory.exploration,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 12,
  ),
  PlayerBehaviorBadge.venueExplorer: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.venueExplorer,
    emoji: '🏟️',
    titleKey: 'playerBadgeVenueExplorerTitle',
    bodyKey: 'playerBadgeVenueExplorerBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.exploration,
    visibility: BadgeVisibility.visible,
    displayOrder: 13,
    levelThresholds: [5, 10, 20, 40, 80],
  ),
  PlayerBehaviorBadge.teamPlayer: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.teamPlayer,
    emoji: '🤝',
    titleKey: 'playerBadgeTeamPlayerTitle',
    bodyKey: 'playerBadgeTeamPlayerBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.community,
    visibility: BadgeVisibility.visible,
    displayOrder: 14,
    // Preparada: requiere co-participantes reales en el historial.
    levelThresholds: [5, 10, 20, 50, 100],
  ),
  PlayerBehaviorBadge.communityBuilder: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.communityBuilder,
    emoji: '🌐',
    titleKey: 'playerBadgeCommunityBuilderTitle',
    bodyKey: 'playerBadgeCommunityBuilderBody',
    rarity: BadgeRarity.epic,
    category: BadgeCategory.community,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 15,
  ),
  PlayerBehaviorBadge.familiarFaces: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.familiarFaces,
    emoji: '👥',
    titleKey: 'playerBadgeFamiliarFacesTitle',
    bodyKey: 'playerBadgeFamiliarFacesBody',
    rarity: BadgeRarity.epic,
    category: BadgeCategory.community,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 16,
  ),
  PlayerBehaviorBadge.earlyBird: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.earlyBird,
    emoji: '🌅',
    titleKey: 'playerBadgeEarlyBirdTitle',
    bodyKey: 'playerBadgeEarlyBirdBody',
    rarity: BadgeRarity.common,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.visible,
    displayOrder: 17,
  ),
  PlayerBehaviorBadge.afterWork: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.afterWork,
    emoji: '🌆',
    titleKey: 'playerBadgeAfterWorkTitle',
    bodyKey: 'playerBadgeAfterWorkBody',
    rarity: BadgeRarity.common,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.visible,
    displayOrder: 18,
  ),
  PlayerBehaviorBadge.nightOwl: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.nightOwl,
    emoji: '🌙',
    titleKey: 'playerBadgeNightOwlTitle',
    bodyKey: 'playerBadgeNightOwlBody',
    rarity: BadgeRarity.common,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.visible,
    displayOrder: 19,
  ),
  PlayerBehaviorBadge.allDayAthlete: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.allDayAthlete,
    emoji: '☀️',
    titleKey: 'playerBadgeAllDayAthleteTitle',
    bodyKey: 'playerBadgeAllDayAthleteBody',
    rarity: BadgeRarity.rare,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 20,
  ),
  PlayerBehaviorBadge.yearRound: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.yearRound,
    emoji: '📅',
    titleKey: 'playerBadgeYearRoundTitle',
    bodyKey: 'playerBadgeYearRoundBody',
    rarity: BadgeRarity.rare,
    category: BadgeCategory.participation,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 21,
  ),
  PlayerBehaviorBadge.rainOrShine: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.rainOrShine,
    emoji: '🌦️',
    titleKey: 'playerBadgeRainOrShineTitle',
    bodyKey: 'playerBadgeRainOrShineBody',
    rarity: BadgeRarity.epic,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 22,
  ),
  PlayerBehaviorBadge.anniversary: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.anniversary,
    emoji: '🎂',
    titleKey: 'playerBadgeAnniversaryTitle',
    bodyKey: 'playerBadgeAnniversaryBody',
    rarity: BadgeRarity.rare,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 23,
  ),
  PlayerBehaviorBadge.fiveYears: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.fiveYears,
    emoji: '🕰️',
    titleKey: 'playerBadgeFiveYearsTitle',
    bodyKey: 'playerBadgeFiveYearsBody',
    rarity: BadgeRarity.legendary,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 24,
  ),
  PlayerBehaviorBadge.weekendWarrior: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.weekendWarrior,
    emoji: '🗓️',
    titleKey: 'playerBadgeWeekendWarriorTitle',
    bodyKey: 'playerBadgeWeekendWarriorBody',
    rarity: BadgeRarity.common,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.visible,
    displayOrder: 25,
  ),
  PlayerBehaviorBadge.earlySeason: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.earlySeason,
    emoji: '🚀',
    titleKey: 'playerBadgeEarlySeasonTitle',
    bodyKey: 'playerBadgeEarlySeasonBody',
    rarity: BadgeRarity.rare,
    category: BadgeCategory.milestones,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 26,
  ),
  PlayerBehaviorBadge.traveler: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.traveler,
    emoji: '🗺️',
    titleKey: 'playerBadgeTravelerTitle',
    bodyKey: 'playerBadgeTravelerBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.exploration,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 27,
  ),
  PlayerBehaviorBadge.winterSpirit: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.winterSpirit,
    emoji: '❄️',
    titleKey: 'playerBadgeWinterSpiritTitle',
    bodyKey: 'playerBadgeWinterSpiritBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 28,
  ),
  PlayerBehaviorBadge.summerSpirit: PlayerBadgeDefinition(
    id: PlayerBehaviorBadge.summerSpirit,
    emoji: '🌞',
    titleKey: 'playerBadgeSummerSpiritTitle',
    bodyKey: 'playerBadgeSummerSpiritBody',
    rarity: BadgeRarity.uncommon,
    category: BadgeCategory.time,
    visibility: BadgeVisibility.hiddenUntilUnlocked,
    displayOrder: 29,
  ),
};

PlayerBadgeDefinition badgeDefinition(PlayerBehaviorBadge id) {
  final def = playerBadgeCatalog[id];
  assert(def != null, 'Falta playerBadgeCatalog[$id]');
  return def!;
}

/// Umbrales de nivel derivados del catálogo (compat / acceso rápido).
Map<PlayerBehaviorBadge, List<int>> get playerBadgeLevelThresholds => {
      for (final e in playerBadgeCatalog.entries)
        if (e.value.hasLevels) e.key: e.value.levelThresholds!,
    };

/// Snapshot de progresión hacia el siguiente nivel.
class BadgeProgression {
  /// 0 = aún no alcanza el nivel 1; 1..[maxLevel] = nivel actual.
  final int currentLevel;
  final int maxLevel;
  final int currentValue;
  /// Umbral ya alcanzado (0 si aún no hay nivel 1).
  final int previousThreshold;
  /// Umbral del próximo nivel; `null` si ya está al máximo.
  final int? nextThreshold;
  /// Avance dentro del tramo actual (`previous` → `next`), o 1.0 si max.
  final double levelProgress;

  const BadgeProgression({
    required this.currentLevel,
    required this.maxLevel,
    required this.currentValue,
    required this.previousThreshold,
    required this.nextThreshold,
    required this.levelProgress,
  });

  bool get unlocked => currentLevel >= 1;
  bool get isMaxed => currentLevel >= maxLevel && maxLevel > 0;
}

/// Resuelve nivel / umbrales / % dentro del tramo a partir de umbrales declarativos.
BadgeProgression resolveBadgeProgression({
  required int currentValue,
  required List<int> thresholds,
}) {
  assert(thresholds.isNotEmpty, 'thresholds no puede estar vacío');
  final levels = List<int>.from(thresholds)..sort();
  final maxLevel = levels.length;
  final value = currentValue < 0 ? 0 : currentValue;

  var currentLevel = 0;
  for (var i = 0; i < levels.length; i++) {
    if (value >= levels[i]) {
      currentLevel = i + 1;
    } else {
      break;
    }
  }

  if (currentLevel >= maxLevel) {
    return BadgeProgression(
      currentLevel: maxLevel,
      maxLevel: maxLevel,
      currentValue: value,
      previousThreshold: levels.last,
      nextThreshold: null,
      levelProgress: 1,
    );
  }

  final previous = currentLevel == 0 ? 0 : levels[currentLevel - 1];
  final next = levels[currentLevel];
  final span = next - previous;
  final levelProgress = span <= 0
      ? 1.0
      : ((value - previous) / span).clamp(0.0, 1.0);

  return BadgeProgression(
    currentLevel: currentLevel,
    maxLevel: maxLevel,
    currentValue: value,
    previousThreshold: previous,
    nextThreshold: next,
    levelProgress: levelProgress,
  );
}

/// Etiqueta romana del nivel (I…X) para UI futura; vacío si level ≤ 0.
String badgeLevelLabel(int level) {
  const romans = [
    '',
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];
  if (level <= 0) return '';
  if (level < romans.length) return romans[level];
  return '$level';
}

class PlayerBehaviorBadgeView {
  final PlayerBehaviorBadge id;
  final bool unlocked;
  final String emoji;

  /// Metadatos de presentación (la UI actual puede ignorarlos).
  final BadgeRarity rarity;
  final BadgeCategory category;
  final BadgeVisibility visibility;
  final int displayOrder;

  /// Campos de progresión (opcionales). La UI actual puede ignorarlos.
  final int? level;
  final int? maxLevel;
  final int? currentValue;
  final int? previousThreshold;
  final int? nextThreshold;
  /// 0.0–1.0 dentro del tramo actual; `null` si la insignia no tiene track.
  final double? levelProgress;

  /// Momento del desbloqueo para historial («Desbloqueada el …»).
  ///
  /// Hoy siempre `null`: no hay persistencia. Cuando exista almacenamiento,
  /// la UI podrá formatear esta fecha sin cambiar el contrato del view.
  final DateTime? unlockedAt;

  const PlayerBehaviorBadgeView({
    required this.id,
    required this.unlocked,
    required this.emoji,
    required this.rarity,
    required this.category,
    required this.visibility,
    required this.displayOrder,
    this.level,
    this.maxLevel,
    this.currentValue,
    this.previousThreshold,
    this.nextThreshold,
    this.levelProgress,
    this.unlockedAt,
  });

  bool get hasProgression => maxLevel != null && maxLevel! > 0;

  PlayerBadgeDefinition get definition => badgeDefinition(id);

  /// Si debe listarse en una colección (respeta [BadgeVisibility]).
  bool get isListedInCollection =>
      visibility == BadgeVisibility.visible || unlocked;
}

PlayerBehaviorBadgeView _simpleBadge({
  required PlayerBehaviorBadge id,
  required bool unlocked,
}) {
  final def = badgeDefinition(id);
  return PlayerBehaviorBadgeView(
    id: id,
    unlocked: unlocked,
    emoji: def.emoji,
    rarity: def.rarity,
    category: def.category,
    visibility: def.visibility,
    displayOrder: def.displayOrder,
    unlockedAt: null,
  );
}

PlayerBehaviorBadgeView _leveledBadge({
  required PlayerBehaviorBadge id,
  required int currentValue,
}) {
  final def = badgeDefinition(id);
  final track = def.levelThresholds;
  assert(
    track != null && track.isNotEmpty,
    'Faltan levelThresholds en catálogo para $id',
  );
  final p = resolveBadgeProgression(
    currentValue: currentValue,
    thresholds: track!,
  );
  return PlayerBehaviorBadgeView(
    id: id,
    unlocked: p.unlocked,
    emoji: def.emoji,
    rarity: def.rarity,
    category: def.category,
    visibility: def.visibility,
    displayOrder: def.displayOrder,
    level: p.currentLevel,
    maxLevel: p.maxLevel,
    currentValue: p.currentValue,
    previousThreshold: p.previousThreshold,
    nextThreshold: p.nextThreshold,
    levelProgress: p.levelProgress,
    unlockedAt: null,
  );
}

/// Filtra para colección futura: oculta sorpresas aún bloqueadas.
List<PlayerBehaviorBadgeView> badgesForCollection(
  Iterable<PlayerBehaviorBadgeView> badges,
) =>
    badges.where((b) => b.isListedInCollection).toList(growable: false);

/// Ordena insignias según [sortBy] (infraestructura para UI futura).
///
/// No muta [badges]. Desempate estable por [PlayerBehaviorBadgeView.displayOrder].
List<PlayerBehaviorBadgeView> sortPlayerBadges(
  Iterable<PlayerBehaviorBadgeView> badges, {
  BadgeSortBy sortBy = BadgeSortBy.displayOrder,
  bool ascending = true,
}) {
  final list = List<PlayerBehaviorBadgeView>.from(badges);
  int cmp(PlayerBehaviorBadgeView a, PlayerBehaviorBadgeView b) {
    final primary = switch (sortBy) {
      BadgeSortBy.displayOrder =>
        a.displayOrder.compareTo(b.displayOrder),
      BadgeSortBy.rarity => a.rarity.index.compareTo(b.rarity.index),
      BadgeSortBy.category => a.category.index.compareTo(b.category.index),
      BadgeSortBy.level => (a.level ?? 0).compareTo(b.level ?? 0),
      BadgeSortBy.unlockedFirst => () {
          if (a.unlocked == b.unlocked) return 0;
          return a.unlocked ? -1 : 1;
        }(),
    };
    if (primary != 0) return ascending ? primary : -primary;
    return a.displayOrder.compareTo(b.displayOrder);
  }

  list.sort(cmp);
  return list;
}

/// Evalúa insignias a partir del historial ya cargado en el perfil.
///
/// Datos opcionales (si faltan, esas insignias quedan bloqueadas pero listadas):
/// - [accountCreatedAt]: necesario para [PlayerBehaviorBadge.earlySeason]
///   («primeros 60 días en Kloovi»).
/// - [encuentrosPorCompanero]: mapa compañeroId → nº de encuentros compartidos.
///   Sin lista de co-participantes por partido (hoy [DetallePartido] solo trae
///   `organizadorId`), [teamPlayer], [communityBuilder] y [familiarFaces]
///   no pueden desbloquearse.
/// - [ciudadesDistintas]: nº de ciudades distintas. [Partido]/[DetallePartido]
///   no exponen ciudad; [traveler] queda pendiente de ese campo.
///
/// Estaciones: hemisferio sur (default del producto, CL) salvo
/// [useSouthernHemisphere] = false.
List<PlayerBehaviorBadgeView> buildPlayerBehaviorBadges({
  required List<DetallePartido> partidos,
  required List<MiConvocatoria> convocatorias,
  required MisInvitacionesResumen invitaciones,
  DateTime? accountCreatedAt,
  Map<String, int>? encuentrosPorCompanero,
  int? ciudadesDistintas,
  bool useSouthernHemisphere = true,
}) {
  final fechas = _fechasEvaluacion(partidos, convocatorias);
  final completed = _encuentrosCompletados(partidos);
  final deportes = _deportes(partidos, convocatorias);
  final recintos = _recintosUnicos(partidos, convocatorias);
  final rachaSemanas = _rachaSemanasConsecutivas(fechas);
  final seasons = <_Season>{
    for (final f in fechas) _seasonOf(f, southern: useSouthernHemisphere),
  };

  final alwaysPresent = _tieneSiemprePresente(partidos, invitaciones);
  final explorer = deportes.length >= 2 || recintos.length >= 2;
  final earlyBird = fechas.any((f) => f.hour < 9);
  final nightOwl = fechas.any((f) => f.hour >= 20);

  final completedCount = completed.length;
  final firstRegistered = () {
    if (fechas.isNotEmpty) {
      return fechas.reduce((a, b) => a.isBefore(b) ? a : b);
    }
    if (completed.isNotEmpty) {
      return completed.reduce((a, b) => a.isBefore(b) ? a : b);
    }
    return null;
  }();

  final weekendCount = fechas
      .where(
        (f) =>
            f.weekday == DateTime.saturday || f.weekday == DateTime.sunday,
      )
      .length;
  final afterWorkCount = fechas.where((f) => f.hour >= 18).length;

  final companionsDistinct = _distinctCompanions(encuentrosPorCompanero);
  final communityBuilder = companionsDistinct >= 100;
  final familiarFaces = _maxSharedWithSame(encuentrosPorCompanero) >= 20;
  final traveler = (ciudadesDistintas ?? 0) >= 5;

  final earlySeason = accountCreatedAt != null &&
      completed.where((f) {
            final delta = f.difference(accountCreatedAt).inDays;
            return delta >= 0 && delta <= 60;
          }).length >=
          10;

  final now = DateTime.now();
  final anniversary = firstRegistered != null &&
      !now.isBefore(DateTime(
        firstRegistered.year + 1,
        firstRegistered.month,
        firstRegistered.day,
      ));
  final fiveYears = firstRegistered != null &&
      !now.isBefore(DateTime(
        firstRegistered.year + 5,
        firstRegistered.month,
        firstRegistered.day,
      ));

  // Orden de evaluación estable; el orden visual futuro usa [displayOrder].
  return [
    _simpleBadge(id: PlayerBehaviorBadge.alwaysPresent, unlocked: alwaysPresent),
    _simpleBadge(id: PlayerBehaviorBadge.explorer, unlocked: explorer),
    _simpleBadge(id: PlayerBehaviorBadge.earlyBird, unlocked: earlyBird),
    _simpleBadge(id: PlayerBehaviorBadge.nightOwl, unlocked: nightOwl),
    _simpleBadge(
      id: PlayerBehaviorBadge.firstStep,
      unlocked: completedCount >= 1,
    ),
    _leveledBadge(
      id: PlayerBehaviorBadge.seasonedPlayer,
      currentValue: completedCount,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.legend,
      unlocked: completedCount >= 500,
    ),
    _leveledBadge(
      id: PlayerBehaviorBadge.streakKeeper,
      currentValue: rachaSemanas,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.unstoppable,
      unlocked: rachaSemanas >= 12,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.consistent,
      unlocked: _mesesConsecutivosConActividad(fechas) >= 6,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.yearRound,
      unlocked: _tieneAnioCompleto(fechas),
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.weekendWarrior,
      unlocked: weekendCount >= 10,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.afterWork,
      unlocked: afterWorkCount >= 15,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.allDayAthlete,
      unlocked: earlyBird && nightOwl,
    ),
    _leveledBadge(
      id: PlayerBehaviorBadge.teamPlayer,
      currentValue: companionsDistinct,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.communityBuilder,
      unlocked: communityBuilder,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.familiarFaces,
      unlocked: familiarFaces,
    ),
    _leveledBadge(
      id: PlayerBehaviorBadge.allRounder,
      currentValue: deportes.length,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.sportCollector,
      unlocked: deportes.length >= 8,
    ),
    _leveledBadge(
      id: PlayerBehaviorBadge.venueExplorer,
      currentValue: recintos.length,
    ),
    _simpleBadge(id: PlayerBehaviorBadge.traveler, unlocked: traveler),
    _simpleBadge(
      id: PlayerBehaviorBadge.winterSpirit,
      unlocked: seasons.contains(_Season.winter),
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.summerSpirit,
      unlocked: seasons.contains(_Season.summer),
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.rainOrShine,
      unlocked: seasons.length >= 4,
    ),
    _simpleBadge(id: PlayerBehaviorBadge.earlySeason, unlocked: earlySeason),
    _simpleBadge(
      id: PlayerBehaviorBadge.milestone50,
      unlocked: completedCount >= 50,
    ),
    _simpleBadge(
      id: PlayerBehaviorBadge.milestone250,
      unlocked: completedCount >= 250,
    ),
    _simpleBadge(id: PlayerBehaviorBadge.anniversary, unlocked: anniversary),
    _simpleBadge(id: PlayerBehaviorBadge.fiveYears, unlocked: fiveYears),
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

/// Fechas de encuentros completados (asistió).
List<DateTime> _encuentrosCompletados(List<DetallePartido> partidos) {
  final out = <DateTime>[];
  for (final p in partidos) {
    if (!p.asistio) continue;
    final f = p.fechaPartido;
    if (f != null) out.add(f);
  }
  return out;
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

int _mesesConsecutivosConActividad(List<DateTime> fechas) {
  if (fechas.isEmpty) return 0;
  final months = fechas.map((f) => DateTime(f.year, f.month)).toSet().toList()
    ..sort();

  var best = 1;
  var streak = 1;
  for (var i = 1; i < months.length; i++) {
    final prev = months[i - 1];
    final expected = DateTime(prev.year, prev.month + 1);
    final cur = months[i];
    if (cur.year == expected.year && cur.month == expected.month) {
      streak++;
      if (streak > best) best = streak;
    } else {
      streak = 1;
    }
  }
  return best;
}

bool _tieneAnioCompleto(List<DateTime> fechas) {
  final byYear = <int, Set<int>>{};
  for (final f in fechas) {
    byYear.putIfAbsent(f.year, () => {}).add(f.month);
  }
  return byYear.values.any((months) => months.length >= 12);
}

int _distinctCompanions(Map<String, int>? map) {
  if (map == null || map.isEmpty) return 0;
  return map.keys.where((k) => k.trim().isNotEmpty).length;
}

int _maxSharedWithSame(Map<String, int>? map) {
  if (map == null || map.isEmpty) return 0;
  var max = 0;
  for (final n in map.values) {
    if (n > max) max = n;
  }
  return max;
}

enum _Season { summer, autumn, winter, spring }

_Season _seasonOf(DateTime f, {required bool southern}) {
  final m = f.month;
  if (southern) {
    if (m == 12 || m == 1 || m == 2) return _Season.summer;
    if (m >= 3 && m <= 5) return _Season.autumn;
    if (m >= 6 && m <= 8) return _Season.winter;
    return _Season.spring;
  }
  if (m == 12 || m == 1 || m == 2) return _Season.winter;
  if (m >= 3 && m <= 5) return _Season.spring;
  if (m >= 6 && m <= 8) return _Season.summer;
  return _Season.autumn;
}

String badgeTitleKey(PlayerBehaviorBadge id) => badgeDefinition(id).titleKey;

String badgeBodyKey(PlayerBehaviorBadge id) => badgeDefinition(id).bodyKey;
