import 'story_models.dart';

/// Motor narrativo «Hoy para ti»: selección pura + contrato de persistencia.
///
/// [getStoryOfTheDay] **no escribe** en el log. Solo filtra y elige.
/// La mutación del historial ocurre exclusivamente en [markStoryAsSeen].
///
/// Convivencia (One Voice Rule):
/// Momento > Memoria > Recordatorio → luego intensidad → priority → id.
abstract class NarrativeEngine {
  /// Ventana de fatiga global para la familia [NarrativeFamily.memoria]
  /// («no más de una Memoria a la semana» por defecto).
  Duration get memoriaFamilyCooldown => const Duration(days: 7);

  /// Elige la única historia del día entre [candidates].
  ///
  /// Función pura respecto a persistencia: no llama a [markStoryAsSeen]
  /// ni altera [log]. Retorna `null` si no hay candidatos elegibles
  /// (silencio fértil).
  StoryCard? getStoryOfTheDay({
    required List<StoryCard> candidates,
    required NarrativeSightingLog log,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final day = NarrativeSightingLog.calendarDay(clock);

    // Sticky: misma voz todo el día calendario (sin re-rankear).
    final sticky = _resolveSticky(
      candidates: candidates,
      log: log,
      day: day,
    );
    if (sticky != null) return sticky;

    final eligible = filterNarrativeCooldowns(
      candidates: candidates,
      log: log,
      now: clock,
      memoriaFamilyCooldown: memoriaFamilyCooldown,
    );
    return pickNarrativeWinner(eligible);
  }

  /// Envuelve el resultado con metadatos de sticky / día (sin mutar el log).
  DailyNarrativeStory? resolveDailyStory({
    required List<StoryCard> candidates,
    required NarrativeSightingLog log,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final day = NarrativeSightingLog.calendarDay(clock);
    final wasSticky = log.hasStickyFor(day) &&
        candidates.any((c) => c.id == log.stickyStoryId);
    final story = getStoryOfTheDay(
      candidates: candidates,
      log: log,
      now: clock,
    );
    if (story == null) return null;
    return DailyNarrativeStory(
      story: story,
      calendarDay: day,
      wasSticky: wasSticky && story.id == log.stickyStoryId,
    );
  }

  /// Registra visualización y cooldowns. **Único** punto de mutación del log.
  Future<void> markStoryAsSeen({
    required String playerId,
    required String storyId,
    NarrativeFamily? family,
    StoryIntensity? intensity,
    Duration? cooldown,
    DateTime? seenAt,
  });

  /// Historial local de visualizaciones (solo lectura desde el caller).
  Future<NarrativeSightingLog> loadSightingLog(String playerId);

  StoryCard? _resolveSticky({
    required List<StoryCard> candidates,
    required NarrativeSightingLog log,
    required DateTime day,
  }) {
    if (!log.hasStickyFor(day)) return null;
    final id = log.stickyStoryId;
    if (id == null) return null;
    for (final c in candidates) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Descarta candidatos en eclipse (cooldown por id / fatiga de Memorias).
List<StoryCard> filterNarrativeCooldowns({
  required List<StoryCard> candidates,
  required NarrativeSightingLog log,
  required DateTime now,
  Duration memoriaFamilyCooldown = const Duration(days: 7),
}) {
  final memoriaFatigue = log.isMemoriaFamilyInCooldown(
    now,
    window: memoriaFamilyCooldown,
  );

  return [
    for (final card in candidates)
      if (!_isEclipsed(
        card: card,
        log: log,
        now: now,
        memoriaFatigue: memoriaFatigue,
      ))
        card,
  ];
}

bool _isEclipsed({
  required StoryCard card,
  required NarrativeSightingLog log,
  required DateTime now,
  required bool memoriaFatigue,
}) {
  if (log.isStoryInCooldown(card.id, now)) return true;
  if (card.family == NarrativeFamily.memoria && memoriaFatigue) return true;
  return false;
}

/// One Voice Rule: familia → intensidad → priority → id.
StoryCard? pickNarrativeWinner(List<StoryCard> eligible) {
  if (eligible.isEmpty) return null;

  var bestRank = -1;
  for (final c in eligible) {
    if (c.familyRank > bestRank) bestRank = c.familyRank;
  }

  final inFamily = [
    for (final c in eligible)
      if (c.familyRank == bestRank) c,
  ];

  inFamily.sort((a, b) {
    final byIntensity = b.intensity.index.compareTo(a.intensity.index);
    if (byIntensity != 0) return byIntensity;
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    return a.id.compareTo(b.id);
  });

  return inFamily.first;
}

/// Resultado diario del motor: carta + contexto de selección.
class DailyNarrativeStory {
  final StoryCard story;

  /// Día calendario (sin hora) al que aplica el sticky.
  final DateTime calendarDay;

  /// true si se reutilizó la carta ya elegida hoy (no se re-rankeó).
  final bool wasSticky;

  const DailyNarrativeStory({
    required this.story,
    required this.calendarDay,
    this.wasSticky = false,
  });

  NarrativeFamily get family => story.family;
  StoryIntensity get intensity => story.intensity;
}
