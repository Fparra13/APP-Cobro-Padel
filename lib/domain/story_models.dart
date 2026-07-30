/// Contratos de datos del motor narrativo «Hoy para ti».
///
/// Tres familias emocionales (visión de producto):
/// - [NarrativeFamily.momento]: celebraciones irrepetibles.
/// - [NarrativeFamily.recordatorio]: conversaciones / near-miss / ritmo.
/// - [NarrativeFamily.memoria]: ecos del pasado; no celebran ni empujan.
///
/// Convivencia (orden de selección):
/// Momento > Memoria > Recordatorio.
///
/// [StoryCategory] sigue describiendo el *tema* (constancia, hitos…).
/// [NarrativeFamily] describe la *voz* emocional.
library;

/// Voz emocional de una historia diaria.
enum NarrativeFamily {
  /// Logro / hito / level-up / récord. Gana siempre a las otras familias.
  momento,

  /// Susurro de progreso o reenganche. Solo si no hay Momento ni Memoria.
  recordatorio,

  /// Eco del pasado. No celebra ni empuja. Escasa («eclipse»).
  memoria,
}

/// Intensidad emocional (UI futura: motion, duración, tratamiento).
enum StoryIntensity {
  low,
  medium,
  high,
  hero,
}

/// Tema narrativo (compat con el Story Engine vigente).
enum StoryCategory {
  /// Rachas y ritmo de juego (delta / continuidad).
  constancia,

  /// Conteos únicos, hitos numéricos y aniversarios de actividad.
  hitos,

  /// Nuevos compañeros y vínculos recurrentes.
  comunidad,

  /// Variedad de deportes o recintos.
  exploracion,

  /// Identidad deportiva / asistencia / arquetipo.
  identidad,

  /// Comparativa temporal vs. el histórico propio.
  evolucion,

  /// Efemérides personales (hace X tiempo…).
  recuerdos,

  /// Patrones ligeros (horarios, días preferidos).
  curiosidades,
}

/// Tipo de ancla temporal / semántica de la historia.
enum StoryAnchorKind {
  /// Desbloqueo o primera vez.
  unlock,

  /// Subida de nivel de insignia.
  levelUp,

  /// Hito numérico (50, 100…).
  milestone,

  /// Racha viva o umbral de racha.
  streak,

  /// Nuevo máximo histórico personal.
  personalBest,

  /// Casi-logro / near miss.
  nearMiss,

  /// Regreso tras inactividad.
  comeback,

  /// Nuevo recinto / deporte / territorio.
  discovery,

  /// Efeméride / aniversario / «hace N…».
  anniversary,

  /// Eco de memoria (silencio largo, reencuentro).
  memoryEcho,

  /// Bienvenida / silencio fértil.
  welcome,
}

/// Metadata opcional para que la UI (futura) sepa *por qué* es esta historia.
class StoryTemporalAnchor {
  final StoryAnchorKind kind;

  /// Cuándo ocurrió el evento narrado (desbloqueo, primer visita…).
  final DateTime? occurredAt;

  /// Fecha origen de un aniversario (primer encuentro, primer recinto…).
  final DateTime? anniversaryOf;

  /// Sujeto estable para cooldowns (`el_peral`, `sport:padel`, badge id…).
  final String? subjectKey;

  /// Datos libres serializables (nivel, remaining, venue label…).
  final Map<String, String> meta;

  const StoryTemporalAnchor({
    required this.kind,
    this.occurredAt,
    this.anniversaryOf,
    this.subjectKey,
    this.meta = const {},
  });
}

/// Historia entregada por el motor a la capa de presentación.
///
/// Agnóstica de widgets: keys l10n + params + familia/intensidad/ancla.
///
/// [id] estable, p. ej. `memoria:primer_recinto:el_peral:2024-08-14`.
class StoryCard {
  final String id;
  final StoryCategory category;
  final NarrativeFamily family;
  final StoryIntensity intensity;

  /// Prioridad numérica dentro de la familia (desempate fino).
  final int priority;

  final String title;
  final String subtitle;
  final String emoji;
  final Map<String, String> params;

  /// Ancla temporal / semántica (aniversario, racha, near-miss…).
  final StoryTemporalAnchor? anchor;

  const StoryCard({
    required this.id,
    required this.category,
    required this.priority,
    required this.title,
    required this.subtitle,
    this.family = NarrativeFamily.recordatorio,
    this.intensity = StoryIntensity.low,
    this.emoji = '✨',
    this.params = const {},
    this.anchor,
  });

  /// Rango de familia para convivencia: Momento(3) > Memoria(2) > Recordatorio(1).
  int get familyRank => narrativeFamilyRank(family);
}

/// Orden de convivencia entre familias (mayor = más prioritario).
int narrativeFamilyRank(NarrativeFamily family) => switch (family) {
      NarrativeFamily.momento => 3,
      NarrativeFamily.memoria => 2,
      NarrativeFamily.recordatorio => 1,
    };

/// Una visualización registrada (para cooldowns / anti-fatiga).
///
/// Equivale a una fila del «historial de lo ya contado».
class StorySighting {
  final String storyId;
  final NarrativeFamily family;
  final StoryIntensity intensity;
  final DateTime seenAt;

  /// Hasta cuándo no reaparecer este [storyId] (eclipses de Memorias).
  final DateTime? cooldownUntil;

  /// Sujeto para no repetir el mismo recinto/persona en cadena.
  final String? subjectKey;

  const StorySighting({
    required this.storyId,
    required this.family,
    required this.intensity,
    required this.seenAt,
    this.cooldownUntil,
    this.subjectKey,
  });

  bool isInCooldown(DateTime now) =>
      cooldownUntil != null && !now.isAfter(cooldownUntil!);
}

/// Estado de memoria local del motor narrativo (por jugador).
///
/// Soporta:
/// - sticky del día calendario
/// - cooldown por `storyId` (Memorias ~11 meses)
/// - fatiga por familia (no dos Memorias seguidas, etc.)
class NarrativeSightingLog {
  /// Visualizaciones recientes (orden cronológico o por [seenAt]).
  final List<StorySighting> sightings;

  /// Historia fijada para [stickyCalendarDay] (misma carta todo el día).
  final String? stickyStoryId;
  final DateTime? stickyCalendarDay;

  /// Última familia mostrada (fatiga entre días).
  final NarrativeFamily? lastFamily;
  final DateTime? lastFamilyAt;

  const NarrativeSightingLog({
    this.sightings = const [],
    this.stickyStoryId,
    this.stickyCalendarDay,
    this.lastFamily,
    this.lastFamilyAt,
  });

  static DateTime calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

  bool hasStickyFor(DateTime day) {
    if (stickyStoryId == null || stickyCalendarDay == null) return false;
    return calendarDay(stickyCalendarDay!) == calendarDay(day);
  }

  StorySighting? latestForStory(String storyId) {
    StorySighting? best;
    for (final s in sightings) {
      if (s.storyId != storyId) continue;
      if (best == null || s.seenAt.isAfter(best.seenAt)) best = s;
    }
    return best;
  }

  bool isStoryInCooldown(String storyId, DateTime now) =>
      latestForStory(storyId)?.isInCooldown(now) ?? false;

  /// Fatiga global de Memorias: hubo una Memoria en la ventana [window].
  ///
  /// Usa [lastFamily]/[lastFamilyAt] y, como respaldo, sightings recientes
  /// de [NarrativeFamily.memoria] (regla «eclipse semanal»).
  bool isMemoriaFamilyInCooldown(
    DateTime now, {
    Duration window = const Duration(days: 7),
  }) {
    if (lastFamily == NarrativeFamily.memoria && lastFamilyAt != null) {
      final elapsed = now.difference(lastFamilyAt!);
      if (elapsed < window) return true;
    }
    final cutoff = now.subtract(window);
    for (final s in sightings) {
      if (s.family != NarrativeFamily.memoria) continue;
      if (!s.seenAt.isBefore(cutoff)) return true;
    }
    return false;
  }
}

/// Señales de entrada del motor (privadas, sin cobros/deudas).
class StoryEngineInput {
  final int encuentrosTotal;
  final int rachaSemanas;
  final int porcentajeAsistencia;
  final int deportesCount;
  final int companeros;
  final int actividadMesActual;
  final int actividadMesAnterior;
  final bool badgeAlwaysPresent;
  final bool badgeExplorer;
  final bool badgeEarlyBird;
  final bool badgeNightOwl;
  final DateTime? primeraActividad;
  final List<DateTime> fechasActividad;

  const StoryEngineInput({
    required this.encuentrosTotal,
    required this.rachaSemanas,
    required this.porcentajeAsistencia,
    required this.deportesCount,
    required this.companeros,
    required this.actividadMesActual,
    required this.actividadMesAnterior,
    this.badgeAlwaysPresent = false,
    this.badgeExplorer = false,
    this.badgeEarlyBird = false,
    this.badgeNightOwl = false,
    this.primeraActividad,
    this.fechasActividad = const [],
  });
}
