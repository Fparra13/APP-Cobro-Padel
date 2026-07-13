import '../core/supabase_helpers.dart';
import '../models/recinto.dart';
import '../utils/maps_location.dart';

class RecintoRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<List<Recinto>> getMisRecintos() async {
    try {
      return await SupabaseHelpers.guard('Listar recintos', () async {
        final uid = SupabaseHelpers.currentUserId;
        if (uid == null) return <Recinto>[];
        final rows = await _client
            .from('recintos')
            .select()
            .eq('organizador_id', uid)
            .order('nombre', ascending: true);
        return (rows as List)
            .map((r) => Recinto.fromSupabaseMap(Map<String, dynamic>.from(r)))
            .toList();
      });
    } catch (_) {
      // Tabla aún no migrada en remoto.
      return [];
    }
  }

  Future<Recinto> crear({
    required String nombre,
    required String mapsInput,
    String? direccion,
  }) async {
    return SupabaseHelpers.write('Crear recinto', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) throw Exception('Sesión requerida');

      final nombreTrim = nombre.trim();
      if (nombreTrim.isEmpty) {
        throw Exception('Indica el nombre del recinto');
      }
      final mapsTrim = mapsInput.trim();
      if (mapsTrim.isEmpty) {
        throw Exception('Pega el link de Google Maps del lugar');
      }

      final parsed = MapsLocation.parseMapsInput(mapsTrim);
      final row = await _client
          .from('recintos')
          .insert({
            'organizador_id': uid,
            'nombre': nombreTrim,
            'direccion': direccion?.trim(),
            'maps_url': parsed.mapsUrl,
            if (parsed.lat != null) 'lat': parsed.lat,
            if (parsed.lng != null) 'lng': parsed.lng,
          })
          .select()
          .single();
      return Recinto.fromSupabaseMap(Map<String, dynamic>.from(row));
    });
  }

  Future<void> eliminar(int id) async {
    await SupabaseHelpers.write('Eliminar recinto', () async {
      await _client.from('recintos').delete().eq('id', id);
    });
  }
}
