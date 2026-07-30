import 'story_models.dart';

/// Contrato del motor narrativo «Hoy para ti».
///
/// No contiene la lógica de detección ni selección (eso vive en una
/// implementación futura). Solo define qué debe poder hacer el motor:
/// entregar la historia del día y registrar visualizaciones para cooldowns.
///
/// Convivencia (prioridad de familia):
/// 1. [NarrativeFamily.momento]
/// 2. [NarrativeFamily.memoria]
/// 3. [NarrativeFamily.recordatorio]
///
/// El motor actual ([StoryEngineService]) sigue siendo el runtime vigente;
/// este contrato es la superficie hacia la que evolucionará.
abstract class NarrativeEngine {
  /// Evalúa señales del jugador y devuelve la historia sticky del día.
  ///
  /// [playerId] identifica al dueño del historial de sightings.
  /// [input] aporta señales ya calculadas en dominio (sin I/O de red aquí).
  /// [now] inyectable para tests / reloj del dispositivo.
  Future<DailyNarrativeStory> getStoryOfTheDay({
    required String playerId,
    required StoryEngineInput input,
    DateTime? now,
  });

  /// Registra que [storyId] fue mostrada (anti-fatiga / eclipses de Memorias).
  ///
  /// Si [cooldown] es null, la implementación elige duración según familia
  /// (p. ej. Memorias ~11 meses; Recordatorios días; Momentos no re-narrar).
  Future<void> markStoryAsSeen({
    required String playerId,
    required String storyId,
    NarrativeFamily? family,
    StoryIntensity? intensity,
    Duration? cooldown,
    DateTime? seenAt,
  });

  /// Historial local de visualizaciones (solo lectura; para debug / políticas).
  Future<NarrativeSightingLog> loadSightingLog(String playerId);
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
