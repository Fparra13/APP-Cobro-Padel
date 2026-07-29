/// Familias emocionales del Story Engine ("Hoy para ti").
///
/// Cada familia agrupa señales privadas de actividad (sin finanzas ni rankings).
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

/// Historia candidata / seleccionada para la tarjeta "Hoy para ti".
///
/// [title] y [subtitle] son keys de l10n (no texto final).
/// [params] alimenta interpolación (`{n}`, `{racha}`, etc.).
class StoryCard {
  final String id;
  final StoryCategory category;
  final int priority;
  final String title;
  final String subtitle;
  final String emoji;
  final Map<String, String> params;

  const StoryCard({
    required this.id,
    required this.category,
    required this.priority,
    required this.title,
    required this.subtitle,
    this.emoji = '✨',
    this.params = const {},
  });
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
