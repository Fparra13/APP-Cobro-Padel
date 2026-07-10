import '../core/supabase_parse.dart';
import 'estado_partido.dart';
import '../core/sport_type.dart';
import '../utils/maps_location.dart';

class Partido {
  final int? id;
  final DateTime fecha;
  final double costoCancha;
  final double costoPelotas;
  final String? recinto;
  final int? recintoId;
  final String? recintoMapsUrl;
  final double? recintoLat;
  final double? recintoLng;
  final String? notas;
  final String? comprobanteCancha;
  final String? comprobantePelotas;
  final EstadoPartido estado;
  final int cuposMax;
  final int horasLimiteRespuesta;
  final SportType sportType;
  final DateTime createdAt;
  final DateTime? resueltoEn;
  final int? partidoOrigenId;
  final DateTime? reprogramadoEn;

  const Partido({
    this.id,
    required this.fecha,
    this.costoCancha = 0,
    this.costoPelotas = 0,
    this.recinto,
    this.recintoId,
    this.recintoMapsUrl,
    this.recintoLat,
    this.recintoLng,
    this.notas,
    this.comprobanteCancha,
    this.comprobantePelotas,
    this.estado = EstadoPartido.jugado,
    this.cuposMax = 4,
    this.horasLimiteRespuesta = 24,
    this.sportType = SportType.padel,
    required this.createdAt,
    this.resueltoEn,
    this.partidoOrigenId,
    this.reprogramadoEn,
  });

  /// Ubicación para abrir en Maps (exacta si hay link/coords).
  MapsLocation get mapsLocation => MapsLocation(
        mapsUrl: recintoMapsUrl,
        lat: recintoLat,
        lng: recintoLng,
        queryFallback: recinto,
      );

  bool get esOrganizando => estado == EstadoPartido.organizando;

  bool get esConfirmado => estado == EstadoPartido.confirmado;

  bool get esCancelado => estado == EstadoPartido.cancelado;

  bool get esConvocatoriaPendiente => esOrganizando || esConfirmado;

  /// Margen tras la hora del partido antes de tratarla como vencida.
  static const convocatoriaGraceAfterMatch = Duration(hours: 6);

  /// Convocatoria sin cerrar cuyo horario del partido ya pasó.
  bool get convocatoriaFechaPasada =>
      esConvocatoriaPendiente && !fecha.isAfter(DateTime.now());

  double get costoFijoTotal => costoCancha + costoPelotas;

  Partido copyWith({
    int? id,
    DateTime? fecha,
    double? costoCancha,
    double? costoPelotas,
    String? recinto,
    int? recintoId,
    String? recintoMapsUrl,
    double? recintoLat,
    double? recintoLng,
    String? notas,
    String? comprobanteCancha,
    String? comprobantePelotas,
    EstadoPartido? estado,
    int? cuposMax,
    int? horasLimiteRespuesta,
    SportType? sportType,
    DateTime? createdAt,
    DateTime? resueltoEn,
    int? partidoOrigenId,
    DateTime? reprogramadoEn,
    bool clearResueltoEn = false,
    bool clearPartidoOrigenId = false,
    bool clearReprogramadoEn = false,
  }) {
    return Partido(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      costoCancha: costoCancha ?? this.costoCancha,
      costoPelotas: costoPelotas ?? this.costoPelotas,
      recinto: recinto ?? this.recinto,
      recintoId: recintoId ?? this.recintoId,
      recintoMapsUrl: recintoMapsUrl ?? this.recintoMapsUrl,
      recintoLat: recintoLat ?? this.recintoLat,
      recintoLng: recintoLng ?? this.recintoLng,
      notas: notas ?? this.notas,
      comprobanteCancha: comprobanteCancha ?? this.comprobanteCancha,
      comprobantePelotas: comprobantePelotas ?? this.comprobantePelotas,
      estado: estado ?? this.estado,
      cuposMax: cuposMax ?? this.cuposMax,
      horasLimiteRespuesta:
          horasLimiteRespuesta ?? this.horasLimiteRespuesta,
      sportType: sportType ?? this.sportType,
      createdAt: createdAt ?? this.createdAt,
      resueltoEn: clearResueltoEn ? null : (resueltoEn ?? this.resueltoEn),
      partidoOrigenId: clearPartidoOrigenId
          ? null
          : (partidoOrigenId ?? this.partidoOrigenId),
      reprogramadoEn: clearReprogramadoEn
          ? null
          : (reprogramadoEn ?? this.reprogramadoEn),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fecha': SupabaseParse.toTimestamptz(fecha),
        'costo_cancha': costoCancha,
        'costo_pelotas': costoPelotas,
        'recinto': recinto,
        'recinto_id': recintoId,
        'recinto_maps_url': recintoMapsUrl,
        'recinto_lat': recintoLat,
        'recinto_lng': recintoLng,
        'notas': notas,
        'comprobante_cancha': comprobanteCancha,
        'comprobante_pelotas': comprobantePelotas,
        'estado': estado.dbValue,
        'cupos_max': cuposMax,
        'horas_limite_respuesta': horasLimiteRespuesta,
        'sport_type': sportType.dbValue,
        'created_at': createdAt.toIso8601String(),
        if (resueltoEn != null) 'resuelto_en': resueltoEn!.toIso8601String(),
        if (partidoOrigenId != null) 'partido_origen_id': partidoOrigenId,
      };

  factory Partido.fromMap(Map<String, dynamic> map) => Partido(
        id: map['id'] as int?,
        fecha: SupabaseParse.toDateTime(map['fecha']),
        costoCancha: (map['costo_cancha'] as num?)?.toDouble() ?? 0,
        costoPelotas: (map['costo_pelotas'] as num?)?.toDouble() ?? 0,
        recinto: map['recinto'] as String?,
        recintoId: map['recinto_id'] as int?,
        recintoMapsUrl: map['recinto_maps_url'] as String?,
        recintoLat: (map['recinto_lat'] as num?)?.toDouble(),
        recintoLng: (map['recinto_lng'] as num?)?.toDouble(),
        notas: map['notas'] as String?,
        comprobanteCancha: map['comprobante_cancha'] as String?,
        comprobantePelotas: map['comprobante_pelotas'] as String?,
        estado: EstadoPartido.fromDb(map['estado'] as String?),
        cuposMax: (map['cupos_max'] as int?) ?? 4,
        horasLimiteRespuesta: (map['horas_limite_respuesta'] as int?) ?? 24,
        sportType: SportType.fromDb(map['sport_type'] as String?),
        createdAt: SupabaseParse.toDateTime(map['created_at']),
        resueltoEn: map['resuelto_en'] != null
            ? SupabaseParse.toDateTime(map['resuelto_en'])
            : null,
        partidoOrigenId: map['partido_origen_id'] as int?,
        reprogramadoEn: map['reprogramado_en'] != null
            ? SupabaseParse.toDateTime(map['reprogramado_en'])
            : null,
      );

  factory Partido.fromSupabaseMap(Map<String, dynamic> map) => Partido(
        id: (map['id'] as num).toInt(),
        fecha: SupabaseParse.toDateTime(map['fecha']),
        costoCancha: (map['costo_cancha'] as num?)?.toDouble() ?? 0,
        costoPelotas: (map['costo_pelotas'] as num?)?.toDouble() ?? 0,
        recinto: map['recinto'] as String?,
        recintoId: map['recinto_id'] is num
            ? (map['recinto_id'] as num).toInt()
            : null,
        recintoMapsUrl: map['recinto_maps_url'] as String?,
        recintoLat: (map['recinto_lat'] as num?)?.toDouble(),
        recintoLng: (map['recinto_lng'] as num?)?.toDouble(),
        notas: map['notas'] as String?,
        comprobanteCancha: map['comprobante_cancha_url'] as String?,
        comprobantePelotas: map['comprobante_pelotas_url'] as String?,
        estado: EstadoPartido.fromDb(map['estado'] as String?),
        cuposMax: (map['cupos_max'] as int?) ?? 4,
        horasLimiteRespuesta: (map['horas_limite_respuesta'] as int?) ?? 24,
        sportType: SportType.fromDb(map['sport_type'] as String?),
        createdAt: SupabaseParse.toDateTime(map['created_at']),
        resueltoEn: map['resuelto_en'] != null
            ? SupabaseParse.toDateTime(map['resuelto_en'])
            : null,
        partidoOrigenId: map['partido_origen_id'] is num
            ? (map['partido_origen_id'] as num).toInt()
            : null,
        reprogramadoEn: map['reprogramado_en'] != null
            ? SupabaseParse.toDateTime(map['reprogramado_en'])
            : null,
      );

  Map<String, dynamic> toSupabaseMap({String? organizadorId}) => {
        if (id != null) 'id': id,
        'fecha': SupabaseParse.toTimestamptz(fecha),
        'costo_cancha': costoCancha,
        'costo_pelotas': costoPelotas,
        'recinto': recinto,
        'recinto_id': recintoId,
        'recinto_maps_url': recintoMapsUrl,
        'recinto_lat': recintoLat,
        'recinto_lng': recintoLng,
        'notas': notas,
        'comprobante_cancha_url': comprobanteCancha,
        'comprobante_pelotas_url': comprobantePelotas,
        'estado': estado.dbValue,
        'cupos_max': cuposMax,
        'horas_limite_respuesta': horasLimiteRespuesta,
        'sport_type': sportType.dbValue,
        if (organizadorId != null) 'organizador_id': organizadorId,
      };
}
