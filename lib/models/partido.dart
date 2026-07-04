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

  bool get esConvocatoriaPendiente => esOrganizando || esConfirmado;

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
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fecha': fecha.toIso8601String(),
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
      };

  factory Partido.fromMap(Map<String, dynamic> map) => Partido(
        id: map['id'] as int?,
        fecha: DateTime.parse(map['fecha'] as String),
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
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  factory Partido.fromSupabaseMap(Map<String, dynamic> map) => Partido(
        id: (map['id'] as num).toInt(),
        fecha: DateTime.parse(map['fecha'] as String),
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
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toSupabaseMap({String? organizadorId}) => {
        if (id != null) 'id': id,
        'fecha': fecha.toIso8601String(),
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
