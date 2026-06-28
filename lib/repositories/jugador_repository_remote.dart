import '../core/supabase_helpers.dart';
import '../models/jugador.dart';

/// Repositorio de jugadores contra Supabase (`profiles`).
class JugadorRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<List<Jugador>> getAll({bool? soloActivos}) async {
    return SupabaseHelpers.guard('Listar jugadores', () async {
      var query = _client.from('profiles').select();
      if (soloActivos == true) {
        query = query.eq('activo', true);
      }
      final rows = await query.order('nombre', ascending: true);
      return (rows as List)
          .map((r) => Jugador.fromSupabaseMap(Map<String, dynamic>.from(r)))
          .toList();
    });
  }

  Future<Jugador?> getById(String id) async {
    return SupabaseHelpers.guard('Obtener jugador', () async {
      final row = await _client.from('profiles').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
    });
  }

  Future<Jugador?> getByTelefono(String telefono) async {
    return SupabaseHelpers.guard('Buscar jugador por teléfono', () async {
      final row = await _client
          .from('profiles')
          .select()
          .eq('telefono', telefono)
          .maybeSingle();
      if (row == null) return null;
      return Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
    });
  }

  /// Registra o actualiza un jugador existente.
  /// Nota: el perfil se crea al iniciar sesión con OTP; el organizador
  /// solo puede actualizar jugadores ya registrados.
  Future<Jugador> crear({
    required String nombre,
    required String telefono,
    bool activo = true,
  }) async {
    final existente = await getByTelefono(telefono);
    if (existente != null) {
      final actualizado = existente.copyWith(
        nombre: nombre.trim(),
        activo: activo,
      );
      await actualizar(actualizado);
      return actualizado;
    }

    throw Exception(
      'El jugador con $telefono debe registrarse primero en la app (OTP). '
      'Después el organizador puede editarlo.',
    );
  }

  Future<void> actualizar(Jugador jugador) async {
    final id = jugador.supabaseId;
    if (id == null) {
      throw Exception('actualizar: jugador sin supabaseId');
    }
    await SupabaseHelpers.guard('Actualizar jugador', () async {
      await _client.from('profiles').update(jugador.toSupabaseMap()).eq('id', id);
    });
  }

  Future<void> toggleActivo(String id, {required bool activo}) async {
    await SupabaseHelpers.guard('Cambiar estado jugador', () async {
      await _client.from('profiles').update({'activo': activo}).eq('id', id);
    });
  }

  Future<void> updateSaldo(String jugadorId, double nuevoSaldo) async {
    await SupabaseHelpers.guard('Actualizar saldo', () async {
      await _client
          .from('profiles')
          .update({'saldo_acumulado': nuevoSaldo})
          .eq('id', jugadorId);
    });
  }

  // Compatibilidad con firmas locales
  Future<int> insert(Jugador jugador) async {
    final creado = await crear(
      nombre: jugador.nombre,
      telefono: jugador.telefono ?? '',
      activo: jugador.activo,
    );
    return creado.supabaseId.hashCode;
  }

  Future<int> update(Jugador jugador) async {
    await actualizar(jugador);
    return 1;
  }

  Future<int> delete(String id) async {
    await SupabaseHelpers.guard('Eliminar jugador', () async {
      await _client.from('profiles').delete().eq('id', id);
    });
    return 1;
  }
}
