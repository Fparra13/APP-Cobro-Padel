import 'package:url_launcher/url_launcher.dart';

/// Ubicación para abrir en Google Maps (link exacto o coordenadas).
///
/// Usa el mismo formato de URL que ya funcionaba en el dispositivo
/// (`maps/search/?api=1&query=...`), con coords cuando hay pin exacto.
class MapsLocation {
  final String? mapsUrl;
  final double? lat;
  final double? lng;
  /// Si no hay link ni coords, busca por este texto (puede ser ambiguo).
  final String? queryFallback;

  const MapsLocation({
    this.mapsUrl,
    this.lat,
    this.lng,
    this.queryFallback,
  });

  bool get hasExactLocation =>
      (mapsUrl != null && mapsUrl!.trim().isNotEmpty) ||
      (lat != null && lng != null);

  /// Misma vía que antes de recintos: URL https de Maps + externalApplication.
  Future<bool> open({String? label}) async {
    final uri = _buildUri(label: label);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Uri? _buildUri({String? label}) {
    final name = (label ?? queryFallback)?.trim();
    final coords = _resolvedCoords;

    // Pin exacto: misma URL de búsqueda, pero con lat,lng (no el link compartido).
    // Los links maps.app.goo.gl / share a veces abren "Servicios de Google Play".
    if (coords != null) {
      final (lat, lng) = coords;
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
    }

    // Sin coords: buscar por nombre (comportamiento que ya te funcionaba).
    if (name != null && name.isNotEmpty) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}',
      );
    }

    return null;
  }

  (double, double)? get _resolvedCoords {
    if (lat != null && lng != null) return (lat!, lng!);
    final url = mapsUrl?.trim();
    if (url == null || url.isEmpty) return null;
    final parsed = parseMapsInput(url);
    if (parsed.lat != null && parsed.lng != null) {
      return (parsed.lat!, parsed.lng!);
    }
    return null;
  }

  /// Extrae coords de un link de Google Maps (si es posible).
  static ({double? lat, double? lng, String mapsUrl}) parseMapsInput(
    String input,
  ) {
    final trimmed = input.trim();
    double? lat;
    double? lng;

    final at = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(trimmed);
    if (at != null) {
      lat = double.tryParse(at.group(1)!);
      lng = double.tryParse(at.group(2)!);
    }

    if (lat == null || lng == null) {
      final q = RegExp(
        r'[?&](?:q|query)=(-?\d+\.\d+),(-?\d+\.\d+)',
      ).firstMatch(trimmed);
      if (q != null) {
        lat = double.tryParse(q.group(1)!);
        lng = double.tryParse(q.group(2)!);
      }
    }

    if (lat == null || lng == null) {
      final d = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(trimmed);
      if (d != null) {
        lat = double.tryParse(d.group(1)!);
        lng = double.tryParse(d.group(2)!);
      }
    }

    if (lat == null || lng == null) {
      final bare = RegExp(r'^(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)$')
          .firstMatch(trimmed);
      if (bare != null) {
        lat = double.tryParse(bare.group(1)!);
        lng = double.tryParse(bare.group(2)!);
      }
    }

    var mapsUrl = trimmed;
    if (!trimmed.startsWith('http') && lat != null && lng != null) {
      mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }

    return (lat: lat, lng: lng, mapsUrl: mapsUrl);
  }
}
