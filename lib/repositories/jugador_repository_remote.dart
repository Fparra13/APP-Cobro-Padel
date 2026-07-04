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
      final row =
          await _client.from('profiles').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
    });
  }

  Future<Jugador?> getByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return SupabaseHelpers.guard('Buscar jugador por email', () async {
      final row = await _client
          .from('profiles')
          .select()
          .eq('email', normalized)
          .maybeSingle();
      if (row == null) return null;
      return Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
    });
  }

  /// Crea o actualiza un jugador por email (no requiere registro previo).
  Future<Jugador> crear({
    required String nombre,
    required String email,
    bool activo = true,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!_esEmailValido(normalized)) {
      throw Exception('Email inválido: $email');
    }

    final existente = await getByEmail(normalized);
    if (existente != null) {
      final actualizado = existente.copyWith(
        nombre: nombre.trim(),
        activo: activo,
        email: normalized,
      );
      await actualizar(actualizado);
      return actualizado;
    }

    return SupabaseHelpers.guard('Crear jugador', () async {
      final row = await _client
          .from('profiles')
          .insert({
            'nombre': nombre.trim(),
            'email': normalized,
            'activo': activo,
            'role': 'jugador',
          })
          .select()
          .single();
      return Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
    });
  }

  Future<void> actualizar(Jugador jugador) async {
    final id = jugador.supabaseId;
    if (id == null) {
      throw Exception('actualizar: jugador sin supabaseId');
    }
    await SupabaseHelpers.guard('Actualizar jugador', () async {
      final payload = Map<String, dynamic>.from(jugador.toSupabaseMap())
        ..remove('id')
        ..remove('saldo_acumulado');
      if (jugador.fotoUrl == null && jugador.fotoPath == null) {
        payload['foto_url'] = null;
      }
      final rows = await _client
          .from('profiles')
          .update(payload)
          .eq('id', id)
          .select('id');
      if ((rows as List).isEmpty) {
        throw Exception(
          'No se pudo guardar. Verifica permisos en Supabase (RLS organizador).',
        );
      }
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

  bool _esEmailValido(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  Future<int> insert(Jugador jugador) async {
    final email = jugador.contactEmail;
    if (email == null || email.isEmpty) {
      throw Exception('El jugador debe tener un email');
    }
    final creado = await crear(
      nombre: jugador.nombre,
      email: email,
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
