import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/narrative_engine.dart';
import '../domain/story_models.dart';
import 'story_engine_service.dart';

/// Implementación local del [NarrativeEngine]:
/// - Candidatos vía [StoryEngineService.buildCandidates]
/// - Selección pura vía [NarrativeEngine.getStoryOfTheDay]
/// - Persistencia de [NarrativeSightingLog] en SharedPreferences
class LocalNarrativeEngine extends NarrativeEngine {
  LocalNarrativeEngine({
    SharedPreferences? prefs,
    StoryEngineService? candidateSource,
    DateTime Function()? clock,
  })  : _prefsOverride = prefs,
        _candidates = candidateSource ?? StoryEngineService(),
        _clock = clock ?? DateTime.now;

  static const _prefsLogPrefix = 'narrative_sighting_log_v1_';

  final SharedPreferences? _prefsOverride;
  final StoryEngineService _candidates;
  final DateTime Function() _clock;

  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? SharedPreferences.getInstance();

  String _logKey(String playerId) => '$_prefsLogPrefix$playerId';

  /// Carga candidatos, aplica enriquecimiento de familia/intensidad y selecciona.
  Future<StoryCard?> fetchStoryOfTheDay({
    required String playerId,
    required StoryEngineInput input,
  }) async {
    final log = await loadSightingLog(playerId);
    final raw = _candidates.buildCandidates(input);
    final enriched = raw.map(enrichCandidate).toList(growable: false);
    return getStoryOfTheDay(
      candidates: enriched,
      log: log,
      now: _clock(),
    );
  }

  @override
  Future<NarrativeSightingLog> loadSightingLog(String playerId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_logKey(playerId));
    if (raw == null || raw.isEmpty) return const NarrativeSightingLog();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _logFromJson(map);
    } catch (_) {
      return const NarrativeSightingLog();
    }
  }

  @override
  Future<void> markStoryAsSeen({
    required String playerId,
    required String storyId,
    NarrativeFamily? family,
    StoryIntensity? intensity,
    Duration? cooldown,
    DateTime? seenAt,
  }) async {
    final now = seenAt ?? _clock();
    final resolvedFamily = family ?? NarrativeFamily.recordatorio;
    final resolvedIntensity = intensity ?? StoryIntensity.low;
    final resolvedCooldown = cooldown ?? defaultCooldownFor(resolvedFamily);

    final current = await loadSightingLog(playerId);
    final sighting = StorySighting(
      storyId: storyId,
      family: resolvedFamily,
      intensity: resolvedIntensity,
      seenAt: now,
      cooldownUntil: now.add(resolvedCooldown),
    );

    final nextSightings = [...current.sightings, sighting];
    // Cap de historial para no crecer sin límite.
    final trimmed = nextSightings.length > 80
        ? nextSightings.sublist(nextSightings.length - 80)
        : nextSightings;

    final next = NarrativeSightingLog(
      sightings: trimmed,
      stickyStoryId: storyId,
      stickyCalendarDay: NarrativeSightingLog.calendarDay(now),
      lastFamily: resolvedFamily,
      lastFamilyAt: now,
    );

    final prefs = await _prefs;
    await prefs.setString(_logKey(playerId), jsonEncode(_logToJson(next)));
  }

  /// Cooldowns por familia (eclipses / anti-fatiga).
  static Duration defaultCooldownFor(NarrativeFamily family) =>
      switch (family) {
        NarrativeFamily.memoria => const Duration(days: 335), // ~11 meses
        NarrativeFamily.momento => const Duration(days: 14),
        NarrativeFamily.recordatorio => const Duration(days: 3),
      };

  /// Asigna voz emocional a candidatos legacy del StoryEngine.
  static StoryCard enrichCandidate(StoryCard card) {
    final classified = _classify(card);
    return StoryCard(
      id: card.id,
      category: card.category,
      priority: card.priority,
      title: card.title,
      subtitle: card.subtitle,
      emoji: card.emoji,
      params: card.params,
      family: classified.family,
      intensity: classified.intensity,
      anchor: classified.anchor ?? card.anchor,
    );
  }

  static ({
    NarrativeFamily family,
    StoryIntensity intensity,
    StoryTemporalAnchor? anchor,
  }) _classify(StoryCard card) {
    final id = card.id;

    if (id.startsWith('recuerdos_')) {
      final years = int.tryParse(card.params['n'] ?? '');
      final now = DateTime.now();
      return (
        family: NarrativeFamily.memoria,
        intensity: StoryIntensity.medium,
        anchor: StoryTemporalAnchor(
          kind: StoryAnchorKind.anniversary,
          anniversaryOf: years == null
              ? null
              : DateTime(now.year - years, now.month, now.day),
        ),
      );
    }

    if (id.startsWith('hitos_encuentro_')) {
      return (
        family: NarrativeFamily.momento,
        intensity: StoryIntensity.high,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.milestone),
      );
    }

    if (id.startsWith('hitos_proximo_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.medium,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.nearMiss),
      );
    }

    if (id.startsWith('constancia_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.medium,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.streak),
      );
    }

    if (id.startsWith('evolucion_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.medium,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.personalBest),
      );
    }

    if (id.startsWith('exploracion_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.medium,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.discovery),
      );
    }

    if (id.startsWith('comunidad_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.medium,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.discovery),
      );
    }

    if (id == 'identidad_welcome') {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.low,
        anchor: const StoryTemporalAnchor(kind: StoryAnchorKind.welcome),
      );
    }

    if (id.startsWith('identidad_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.medium,
        anchor: null,
      );
    }

    if (id.startsWith('curiosidades_')) {
      return (
        family: NarrativeFamily.recordatorio,
        intensity: StoryIntensity.low,
        anchor: null,
      );
    }

    return (
      family: NarrativeFamily.recordatorio,
      intensity: StoryIntensity.low,
      anchor: null,
    );
  }

  static Map<String, dynamic> _logToJson(NarrativeSightingLog log) => {
        'stickyStoryId': log.stickyStoryId,
        'stickyCalendarDay': log.stickyCalendarDay?.toIso8601String(),
        'lastFamily': log.lastFamily?.name,
        'lastFamilyAt': log.lastFamilyAt?.toIso8601String(),
        'sightings': [
          for (final s in log.sightings)
            {
              'storyId': s.storyId,
              'family': s.family.name,
              'intensity': s.intensity.name,
              'seenAt': s.seenAt.toIso8601String(),
              'cooldownUntil': s.cooldownUntil?.toIso8601String(),
              'subjectKey': s.subjectKey,
            },
        ],
      };

  static NarrativeSightingLog _logFromJson(Map<String, dynamic> map) {
    final sightingsRaw = map['sightings'] as List<dynamic>? ?? const [];
    final sightings = <StorySighting>[];
    for (final item in sightingsRaw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final familyName = m['family'] as String?;
      final intensityName = m['intensity'] as String?;
      final seenAt = DateTime.tryParse(m['seenAt'] as String? ?? '');
      if (familyName == null || intensityName == null || seenAt == null) {
        continue;
      }
      sightings.add(
        StorySighting(
          storyId: m['storyId'] as String? ?? '',
          family: NarrativeFamily.values.firstWhere(
            (f) => f.name == familyName,
            orElse: () => NarrativeFamily.recordatorio,
          ),
          intensity: StoryIntensity.values.firstWhere(
            (i) => i.name == intensityName,
            orElse: () => StoryIntensity.low,
          ),
          seenAt: seenAt,
          cooldownUntil: DateTime.tryParse(m['cooldownUntil'] as String? ?? ''),
          subjectKey: m['subjectKey'] as String?,
        ),
      );
    }

    final lastFamilyName = map['lastFamily'] as String?;
    return NarrativeSightingLog(
      sightings: sightings,
      stickyStoryId: map['stickyStoryId'] as String?,
      stickyCalendarDay:
          DateTime.tryParse(map['stickyCalendarDay'] as String? ?? ''),
      lastFamily: lastFamilyName == null
          ? null
          : NarrativeFamily.values.firstWhere(
              (f) => f.name == lastFamilyName,
              orElse: () => NarrativeFamily.recordatorio,
            ),
      lastFamilyAt: DateTime.tryParse(map['lastFamilyAt'] as String? ?? ''),
    );
  }
}
