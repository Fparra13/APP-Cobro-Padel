import 'estado_partido.dart';
import 'jugador.dart';
import 'partido.dart';

/// Payload al crear/actualizar filas de convocatoria.
class ConvocatoriaJugadorInput {
  final String jugadorId;
  final bool esSuplente;
  final int? ordenEspera;
  final EstadoConfirmacion estado;

  const ConvocatoriaJugadorInput({
    required this.jugadorId,
    this.esSuplente = false,
    this.ordenEspera,
    this.estado = EstadoConfirmacion.invitado,
  });
}

class ConvocatoriaJugadorEntry {
  final int? id;
  final int partidoId;
  final Jugador jugador;
  final EstadoConfirmacion estado;
  final bool esSuplente;
  final int? ordenEspera;
  final DateTime? tiempoLimite;
  final bool notificadoVencimiento;
  final bool recordatorioPlazoEnviado;

  const ConvocatoriaJugadorEntry({
    this.id,
    required this.partidoId,
    required this.jugador,
    required this.estado,
    this.esSuplente = false,
    this.ordenEspera,
    this.tiempoLimite,
    this.notificadoVencimiento = false,
    this.recordatorioPlazoEnviado = false,
  });

  bool get esTitular => !esSuplente;

  bool get tiempoVencido {
    if (tiempoLimite == null) return false;
    return DateTime.now().isAfter(tiempoLimite!);
  }

  ConvocatoriaJugadorEntry copyWith({
    int? id,
    int? partidoId,
    Jugador? jugador,
    EstadoConfirmacion? estado,
    bool? esSuplente,
    int? ordenEspera,
    DateTime? tiempoLimite,
    bool? notificadoVencimiento,
    bool? recordatorioPlazoEnviado,
    bool clearOrdenEspera = false,
    bool clearTiempoLimite = false,
  }) {
    return ConvocatoriaJugadorEntry(
      id: id ?? this.id,
      partidoId: partidoId ?? this.partidoId,
      jugador: jugador ?? this.jugador,
      estado: estado ?? this.estado,
      esSuplente: esSuplente ?? this.esSuplente,
      ordenEspera:
          clearOrdenEspera ? null : (ordenEspera ?? this.ordenEspera),
      tiempoLimite:
          clearTiempoLimite ? null : (tiempoLimite ?? this.tiempoLimite),
      notificadoVencimiento:
          notificadoVencimiento ?? this.notificadoVencimiento,
      recordatorioPlazoEnviado:
          recordatorioPlazoEnviado ?? this.recordatorioPlazoEnviado,
    );
  }

  factory ConvocatoriaJugadorEntry.fromMap(
    Map<String, dynamic> map,
    Jugador jugador,
  ) {
    final tiempoRaw = map['tiempo_limite'];
    return ConvocatoriaJugadorEntry(
      id: map['id'] as int?,
      partidoId: map['partido_id'] as int,
      jugador: jugador,
      estado: EstadoConfirmacion.fromDb(map['estado_confirmacion'] as String?),
      esSuplente: (map['es_suplente'] as int? ?? 0) == 1 ||
          map['es_suplente'] == true,
      ordenEspera: map['orden_espera'] as int?,
      tiempoLimite: tiempoRaw != null
          ? DateTime.parse(tiempoRaw.toString())
          : null,
      notificadoVencimiento: (map['notificado_vencimiento'] as int? ?? 0) ==
              1 ||
          map['notificado_vencimiento'] == true,
      recordatorioPlazoEnviado:
          (map['recordatorio_plazo_enviado'] as int? ?? 0) == 1 ||
              map['recordatorio_plazo_enviado'] == true,
    );
  }

  static ConvocatoriaJugadorEntry fromSupabaseRow(
    Map<String, dynamic> map,
    Jugador jugador,
    int partidoId,
  ) {
    final tiempoRaw = map['tiempo_limite'];
    return ConvocatoriaJugadorEntry(
      id: (map['id'] as num?)?.toInt(),
      partidoId: partidoId,
      jugador: jugador,
      estado: EstadoConfirmacion.fromDb(map['estado_confirmacion'] as String?),
      esSuplente: map['es_suplente'] as bool? ?? false,
      ordenEspera: (map['orden_espera'] as num?)?.toInt(),
      tiempoLimite: tiempoRaw != null
          ? DateTime.parse(tiempoRaw.toString())
          : null,
      notificadoVencimiento: map['notificado_vencimiento'] as bool? ?? false,
      recordatorioPlazoEnviado:
          map['recordatorio_plazo_enviado'] as bool? ?? false,
    );
  }
}

class ConvocatoriaCompleta {
  final Partido partido;
  final List<ConvocatoriaJugadorEntry> jugadores;

  const ConvocatoriaCompleta({
    required this.partido,
    required this.jugadores,
  });

  int get confirmados => jugadores
      .where((j) => !j.esSuplente && j.estado == EstadoConfirmacion.confirmado)
      .length;

  int get pendientes => jugadores
      .where((j) => !j.esSuplente && j.estado == EstadoConfirmacion.invitado)
      .length;

  int get enEspera => jugadores.where((j) => j.esSuplente).length;

  int get invitados => jugadores.length;

  int get rechazados => jugadores
      .where((j) =>
          j.estado == EstadoConfirmacion.rechazado ||
          j.estado == EstadoConfirmacion.noRespondio)
      .length;

  List<ConvocatoriaJugadorEntry> get titulares => jugadores
      .where((j) => !j.esSuplente)
      .toList()
    ..sort((a, b) => a.jugador.nombre.compareTo(b.jugador.nombre));

  List<ConvocatoriaJugadorEntry> get suplentes => jugadores
      .where((j) => j.esSuplente)
      .toList()
    ..sort((a, b) => (a.ordenEspera ?? 999).compareTo(b.ordenEspera ?? 999));
}
