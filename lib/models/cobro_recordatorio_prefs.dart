/// Preferencias de recordatorios automáticos de cobro (servidor).
class CobroRecordatorioPrefs {
  final bool activo;
  final int diasPrimer;
  final int frecuenciaDias;
  final TimeOfDayLike horaLocal;
  final String timezone;
  final bool exists;

  const CobroRecordatorioPrefs({
    required this.activo,
    required this.diasPrimer,
    required this.frecuenciaDias,
    required this.horaLocal,
    required this.timezone,
    this.exists = false,
  });

  static const defaults = CobroRecordatorioPrefs(
    activo: false,
    diasPrimer: 3,
    frecuenciaDias: 3,
    horaLocal: TimeOfDayLike(hour: 10, minute: 0),
    timezone: 'America/Santiago',
    exists: false,
  );

  /// Opciones UI: primer aviso.
  static const primerOpciones = [1, 3, 7];

  /// Opciones UI: repetición mientras siga pendiente.
  static const frecuenciaOpciones = [2, 3, 7];

  /// Mapea valores legacy (p. ej. 15) a una opción V1 válida.
  static int normalizeFrecuencia(int value) {
    if (frecuenciaOpciones.contains(value)) return value;
    // Legacy "cada 15 días" → cada 7 días.
    if (value == 15) return 7;
    return _nearest(value, frecuenciaOpciones);
  }

  static int normalizePrimer(int value) {
    if (primerOpciones.contains(value)) return value;
    return _nearest(value, primerOpciones);
  }

  static int _nearest(int value, List<int> options) {
    var best = options.first;
    var bestDist = (value - best).abs();
    for (final o in options.skip(1)) {
      final d = (value - o).abs();
      if (d < bestDist) {
        best = o;
        bestDist = d;
      }
    }
    return best;
  }

  factory CobroRecordatorioPrefs.fromJson(Map<String, dynamic> json) {
    final horaRaw = json['hora_local']?.toString() ?? '10:00:00';
    final rawFreq = (json['frecuencia_dias'] as num?)?.toInt() ?? 3;
    final rawPrimer = (json['dias_primer'] as num?)?.toInt() ?? 3;
    return CobroRecordatorioPrefs(
      activo: json['activo'] as bool? ?? false,
      diasPrimer: normalizePrimer(rawPrimer),
      frecuenciaDias: normalizeFrecuencia(rawFreq),
      horaLocal: TimeOfDayLike.parse(horaRaw),
      timezone: (json['timezone'] as String?)?.trim().isNotEmpty == true
          ? (json['timezone'] as String).trim()
          : 'America/Santiago',
      exists: json['exists'] as bool? ?? true,
    );
  }

  String get horaLocalSql =>
      '${horaLocal.hour.toString().padLeft(2, '0')}:'
      '${horaLocal.minute.toString().padLeft(2, '0')}:00';

  CobroRecordatorioPrefs copyWith({
    bool? activo,
    int? diasPrimer,
    int? frecuenciaDias,
    TimeOfDayLike? horaLocal,
    String? timezone,
    bool? exists,
  }) {
    return CobroRecordatorioPrefs(
      activo: activo ?? this.activo,
      diasPrimer: diasPrimer ?? this.diasPrimer,
      frecuenciaDias: frecuenciaDias ?? this.frecuenciaDias,
      horaLocal: horaLocal ?? this.horaLocal,
      timezone: timezone ?? this.timezone,
      exists: exists ?? this.exists,
    );
  }
}

/// Hora sin dependencia de Flutter Material (tests / repos).
class TimeOfDayLike {
  final int hour;
  final int minute;

  const TimeOfDayLike({required this.hour, required this.minute});

  factory TimeOfDayLike.parse(String raw) {
    final parts = raw.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 10;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDayLike(
      hour: h.clamp(0, 23),
      minute: m.clamp(0, 59),
    );
  }
}

class GenerarRecordatoriosPartidoResult {
  final bool ok;
  final bool generar;
  final int creados;
  final int omitidos;
  final bool prefsActivo;
  final String? mensaje;

  const GenerarRecordatoriosPartidoResult({
    required this.ok,
    required this.generar,
    required this.creados,
    required this.omitidos,
    required this.prefsActivo,
    this.mensaje,
  });

  factory GenerarRecordatoriosPartidoResult.fromJson(Map<String, dynamic> json) {
    return GenerarRecordatoriosPartidoResult(
      ok: json['ok'] as bool? ?? true,
      generar: json['generar'] as bool? ?? false,
      creados: (json['creados'] as num?)?.toInt() ?? 0,
      omitidos: (json['omitidos'] as num?)?.toInt() ?? 0,
      prefsActivo: json['prefs_activo'] as bool? ?? false,
      mensaje: json['mensaje'] as String?,
    );
  }
}
