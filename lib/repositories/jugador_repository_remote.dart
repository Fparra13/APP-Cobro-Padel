import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Crea o actualiza un jugador (email opcional; vincula por correo si existe).
  Future<Jugador> crear({
    required String nombre,
    String? email,
    String? telefono,
    bool activo = true,
  }) async {
    final trimmedName = nombre.trim();
    if (trimmedName.isEmpty) {
      throw Exception('El jugador debe tener un nombre');
    }

    final mailRaw = email?.trim().toLowerCase();
    final mail = (mailRaw != null && mailRaw.isNotEmpty) ? mailRaw : null;
    if (mail != null && !_esEmailValido(mail)) {
      throw Exception('Email inválido: $email');
    }

    final telRaw = telefono?.trim();
    final tel = (telRaw != null && telRaw.isNotEmpty) ? telRaw : null;

    if (mail != null) {
      final existente = await getByEmail(mail);
      if (existente != null) {
        final actualizado = existente.copyWith(
          nombre: trimmedName,
          activo: activo,
          email: mail,
          telefono: tel ?? existente.telefono,
        );
        await actualizar(actualizado);
        return actualizado;
      }
    }

    return SupabaseHelpers.guard('Crear jugador', () async {
      try {
        final row = await _client.rpc(
          'crear_jugador_organizador',
          params: {
            'p_nombre': trimmedName,
            'p_email': mail,
            'p_telefono': tel,
            'p_activo': activo,
          },
        );
        return Jugador.fromSupabaseMap(
          Map<String, dynamic>.from(row as Map),
        );
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        // RPC aún no desplegada: fallback directo.
      }

      final payload = <String, dynamic>{
        'nombre': trimmedName,
        'activo': activo,
        'role': 'jugador',
      };
      if (mail != null) payload['email'] = mail;
      if (tel != null) payload['telefono'] = tel;
      final row = await _client
          .from('profiles')
          .insert(payload)
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
    final creado = await crear(
      nombre: jugador.nombre,
      email: jugador.contactEmail,
      telefono: jugador.contactWhatsApp,
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
