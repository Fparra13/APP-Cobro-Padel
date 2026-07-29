import 'package:shared_preferences/shared_preferences.dart';

import '../domain/story_models.dart';

/// Motor de historias para "Hoy para ti".
///
/// Flujo:
/// 1. Genera candidatos por las 8 [StoryCategory].
/// 2. Filtra anti-fatiga (mismo `id` en cooldown; misma familia en días consecutivos).
/// 3. Elige el de mayor [StoryCard.priority] (empate → id estable).
/// 4. Persiste la selección localmente (sin backend).
///
/// En el mismo día calendario reutiliza la historia ya mostrada (sticky).
class StoryEngineService {
  StoryEngineService({
    SharedPreferences? prefs,
    DateTime Function()? clock,
    this.storyCooldownDays = 3,
  })  : _prefsOverride = prefs,
        _clock = clock ?? DateTime.now;

  static const _prefsLastId = 'story_engine_last_id';
  static const _prefsLastCategory = 'story_engine_last_category';
  static const _prefsLastAt = 'story_engine_last_at';

  final SharedPreferences? _prefsOverride;
  final DateTime Function() _clock;

  /// Días calendario sin repetir el mismo `storyId`.
  final int storyCooldownDays;

  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? SharedPreferences.getInstance();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Selecciona la historia del día y registra anti-fatiga.
  Future<StoryCard> selectStory(StoryEngineInput input) async {
    final candidates = buildCandidates(input);
    final prefs = await _prefs;
    final lastId = prefs.getString(_prefsLastId);
    final lastAtRaw = prefs.getString(_prefsLastAt);
    final lastAt = lastAtRaw == null ? null : DateTime.tryParse(lastAtRaw);
    final now = _clock();

    // Sticky: misma historia durante el día calendario.
    if (lastId != null &&
        lastAt != null &&
        _dateOnly(lastAt) == _dateOnly(now)) {
      for (final card in candidates) {
        if (card.id == lastId) return card;
      }
    }

    final filtered = _applyAntiFatigue(
      candidates,
      lastId: lastId,
      lastCategory: prefs.getString(_prefsLastCategory),
      lastAt: lastAt,
      now: now,
    );
    final pool = filtered.isNotEmpty
        ? filtered
        : _softFallback(
            candidates,
            lastId: lastId,
            lastCategory: prefs.getString(_prefsLastCategory),
            lastAt: lastAt,
            now: now,
          );
    final selected = _pickHighestPriority(pool);
    await _rememberSelection(selected);
    return selected;
  }

  /// Candidatos elegibles (sin filtrar cooldown).
  List<StoryCard> buildCandidates(StoryEngineInput input) {
    final cards = <StoryCard>[
      ..._candidatesConstancia(input),
      ..._candidatesHitos(input),
      ..._candidatesComunidad(input),
      ..._candidatesExploracion(input),
      ..._candidatesIdentidad(input),
      ..._candidatesEvolucion(input),
      ..._candidatesRecuerdos(input),
      ..._candidatesCuriosidades(input),
    ];
    if (cards.isEmpty) cards.add(_fallbackWelcome());
    return cards;
  }

  // —— Familias ————————————————————————————————————————————————

  List<StoryCard> _candidatesConstancia(StoryEngineInput input) {
    if (input.rachaSemanas < 2) return const [];
    return [
      StoryCard(
        id: 'constancia_racha_${input.rachaSemanas}',
        category: StoryCategory.constancia,
        priority: 85,
        title: 'playerTodayStreakTitle',
        subtitle: 'playerTodayStreakBody',
        emoji: '🔥',
        params: {'racha': '${input.rachaSemanas}'},
      ),
    ];
  }

  List<StoryCard> _candidatesHitos(StoryEngineInput input) {
    final n = input.encuentrosTotal;
    if (n >= 10 && n % 10 == 0) {
      return [
        StoryCard(
          id: 'hitos_encuentro_$n',
          category: StoryCategory.hitos,
          priority: 95,
          title: 'playerTodayMilestoneTitle',
          subtitle: 'playerTodayMilestoneBody',
          emoji: '🎉',
          params: {'n': '$n'},
        ),
      ];
    }
    if (n > 0) {
      final remaining = (((n ~/ 10) + 1) * 10 - n).clamp(1, 10);
      return [
        StoryCard(
          id: 'hitos_proximo_$n',
          category: StoryCategory.hitos,
          priority: 72,
          title: 'playerTodayNextGoalTitle',
          subtitle: 'playerTodayNextGoalBody',
          emoji: '🎯',
          params: {'n': '$remaining'},
        ),
      ];
    }
    return const [];
  }

  List<StoryCard> _candidatesComunidad(StoryEngineInput input) {
    if (input.companeros <= 0 && input.actividadMesActual <= 0) {
      return const [];
    }
    final n =
        input.companeros > 0 ? input.companeros : input.actividadMesActual;
    return [
      StoryCard(
        id: 'comunidad_vinculo_$n',
        category: StoryCategory.comunidad,
        priority: 70,
        title: 'playerTodayCommunityTitle',
        subtitle: 'playerTodayCommunityBody',
        emoji: '🤝',
        params: {'n': '$n'},
      ),
    ];
  }

  List<StoryCard> _candidatesExploracion(StoryEngineInput input) {
    if (!input.badgeExplorer && input.deportesCount < 2) return const [];
    final n = input.deportesCount < 2 ? 2 : input.deportesCount;
    return [
      StoryCard(
        id: 'exploracion_deportes_$n',
        category: StoryCategory.exploracion,
        priority: 65,
        title: 'playerStoryExploreTitle',
        subtitle: 'playerStoryExploreBody',
        emoji: '🧭',
        params: {'n': '$n'},
      ),
    ];
  }

  List<StoryCard> _candidatesIdentidad(StoryEngineInput input) {
    if (!input.badgeAlwaysPresent && input.porcentajeAsistencia < 80) {
      return const [];
    }
    return [
      StoryCard(
        id: 'identidad_asistencia_${input.porcentajeAsistencia}',
        category: StoryCategory.identidad,
        priority: 60,
        title: 'playerStoryIdentityTitle',
        subtitle: 'playerStoryIdentityBody',
        emoji: '🏆',
        params: {'n': '${input.porcentajeAsistencia}'},
      ),
    ];
  }

  List<StoryCard> _candidatesEvolucion(StoryEngineInput input) {
    final actual = input.actividadMesActual;
    final prev = input.actividadMesAnterior;
    if (actual <= 0 || actual <= prev) return const [];
    return [
      StoryCard(
        id: 'evolucion_mes_${actual}_vs_$prev',
        category: StoryCategory.evolucion,
        priority: 75,
        title: 'playerStoryEvolutionTitle',
        subtitle: 'playerStoryEvolutionBody',
        emoji: '📈',
        params: {
          'actual': '$actual',
          'prev': '$prev',
        },
      ),
    ];
  }

  List<StoryCard> _candidatesRecuerdos(StoryEngineInput input) {
    final first = input.primeraActividad;
    if (first == null) return const [];
    final now = _clock();
    final years = now.year - first.year;
    final sameDay = now.month == first.month && now.day == first.day;
    if (!sameDay || years < 1) return const [];
    return [
      StoryCard(
        id: 'recuerdos_aniversario_$years',
        category: StoryCategory.recuerdos,
        priority: 90,
        title: 'playerStoryMemoryTitle',
        subtitle: 'playerStoryMemoryBody',
        emoji: '📷',
        params: {'n': '$years'},
      ),
    ];
  }

  List<StoryCard> _candidatesCuriosidades(StoryEngineInput input) {
    if (input.badgeEarlyBird) {
      return const [
        StoryCard(
          id: 'curiosidades_madrugador',
          category: StoryCategory.curiosidades,
          priority: 40,
          title: 'playerStoryCuriosityEarlyTitle',
          subtitle: 'playerStoryCuriosityEarlyBody',
          emoji: '🌅',
        ),
      ];
    }
    if (input.badgeNightOwl) {
      return const [
        StoryCard(
          id: 'curiosidades_nocturno',
          category: StoryCategory.curiosidades,
          priority: 40,
          title: 'playerStoryCuriosityNightTitle',
          subtitle: 'playerStoryCuriosityNightBody',
          emoji: '🌙',
        ),
      ];
    }
    final preferred = _preferredWeekday(input.fechasActividad);
    if (preferred == null) return const [];
    return [
      StoryCard(
        id: 'curiosidades_dia_$preferred',
        category: StoryCategory.curiosidades,
        priority: 35,
        title: 'playerStoryCuriosityDayTitle',
        subtitle: 'playerStoryCuriosityDayBody',
        emoji: '🗓️',
        params: {'day': '$preferred'},
      ),
    ];
  }

  StoryCard _fallbackWelcome() {
    return const StoryCard(
      id: 'identidad_welcome',
      category: StoryCategory.identidad,
      priority: 10,
      title: 'playerTodayWelcomeTitle',
      subtitle: 'playerTodayWelcomeBody',
      emoji: '✨',
    );
  }

  // —— Selección / anti-fatiga ————————————————————————————————

  StoryCard _pickHighestPriority(List<StoryCard> cards) {
    final sorted = [...cards]
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
        return a.id.compareTo(b.id);
      });
    return sorted.first;
  }

  /// Misma categoría no se repite el mismo día ni el día siguiente.
  /// Mismo `id` no se repite durante [storyCooldownDays] días calendario.
  List<StoryCard> _applyAntiFatigue(
    List<StoryCard> cards, {
    required String? lastId,
    required String? lastCategory,
    required DateTime? lastAt,
    required DateTime now,
  }) {
    if (lastAt == null) return cards;
    final daysApart = _dateOnly(now).difference(_dateOnly(lastAt)).inDays;

    return cards.where((card) {
      if (lastId == card.id && daysApart < storyCooldownDays) return false;
      if (lastCategory == card.category.name && daysApart <= 1) return false;
      return true;
    }).toList();
  }

  /// Si todo quedó filtrado: prioriza otra familia; si no hay, permite pool original.
  List<StoryCard> _softFallback(
    List<StoryCard> candidates, {
    required String? lastId,
    required String? lastCategory,
    required DateTime? lastAt,
    required DateTime now,
  }) {
    if (lastAt == null) return candidates;
    final daysApart = _dateOnly(now).difference(_dateOnly(lastAt)).inDays;
    final otherFamily = candidates.where((card) {
      if (lastCategory == card.category.name && daysApart <= 1) return false;
      return true;
    }).toList();
    if (otherFamily.isNotEmpty) return otherFamily;
    return candidates
        .where((c) => !(lastId == c.id && daysApart < storyCooldownDays))
        .toList()
        .ifEmpty(candidates);
  }

  Future<void> _rememberSelection(StoryCard card) async {
    final prefs = await _prefs;
    await prefs.setString(_prefsLastId, card.id);
    await prefs.setString(_prefsLastCategory, card.category.name);
    await prefs.setString(_prefsLastAt, _clock().toIso8601String());
  }

  /// ISO weekday 1=lunes … 7=domingo con al menos 2 apariciones.
  static int? _preferredWeekday(List<DateTime> dates) {
    if (dates.length < 3) return null;
    final counts = <int, int>{};
    for (final d in dates) {
      counts[d.weekday] = (counts[d.weekday] ?? 0) + 1;
    }
    var bestDay = 1;
    var bestCount = 0;
    counts.forEach((day, count) {
      if (count > bestCount) {
        bestDay = day;
        bestCount = count;
      }
    });
    if (bestCount < 2) return null;
    return bestDay;
  }
}

extension _ListIfEmpty<T> on List<T> {
  List<T> ifEmpty(List<T> fallback) => isEmpty ? fallback : this;
}
