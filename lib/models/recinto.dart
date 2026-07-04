import '../core/supabase_parse.dart';
import '../utils/maps_location.dart';

/// Recinto guardado por el organizador (nombre + ubicación exacta en Maps).
class Recinto {
  final int? id;
  final String? organizadorId;
  final String nombre;
  final String? direccion;
  final String mapsUrl;
  final double? lat;
  final double? lng;
  final DateTime createdAt;

  const Recinto({
    this.id,
    this.organizadorId,
    required this.nombre,
    this.direccion,
    required this.mapsUrl,
    this.lat,
    this.lng,
    required this.createdAt,
  });

  MapsLocation get location => MapsLocation(
        mapsUrl: mapsUrl,
        lat: lat,
        lng: lng,
        queryFallback: nombre,
      );

  factory Recinto.fromSupabaseMap(Map<String, dynamic> map) => Recinto(
        id: map['id'] is num ? (map['id'] as num).toInt() : null,
        organizadorId: SupabaseParse.toStringOrNull(map['organizador_id']),
        nombre: SupabaseParse.asString(map['nombre']),
        direccion: SupabaseParse.toStringOrNull(map['direccion']),
        mapsUrl: SupabaseParse.asString(map['maps_url']),
        lat: map['lat'] is num ? (map['lat'] as num).toDouble() : null,
        lng: map['lng'] is num ? (map['lng'] as num).toDouble() : null,
        createdAt: SupabaseParse.toDateTime(map['created_at']),
      );

  Map<String, dynamic> toInsertMap(String organizadorId) => {
        'organizador_id': organizadorId,
        'nombre': nombre.trim(),
        'direccion': direccion?.trim(),
        'maps_url': mapsUrl.trim(),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };
}
