import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_helpers.dart';
import '../models/jugador.dart';

/// Repositorio de jugadores contra Supabase (`profiles`).
class JugadorRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<List<Jugador>> getAll({
    bool? soloActivos,
    bool incluirUsuarioActual = false,
  }) async {
    return SupabaseHelpers.guard('Listar jugadores', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return [];

      final jugadores = <Jugador>[];
      final seen = <String>{};

      // Preferir RPC (SECURITY DEFINER): estable con RLS de aislamiento.
      try {
        final raw = await _client.rpc(
          'get_mis_jugadores_organizador',
          params: {'p_solo_activos': soloActivos},
        );
        if (raw is List) {
          for (final item in raw) {
            if (item is! Map) continue;
            final jugador = Jugador.fromSupabaseMap(
              Map<String, dynamic>.from(item),
            );
            final id = jugador.supabaseId;
            if (id != null) seen.add(id);
            jugadores.add(jugador);
          }
        }
      } catch (_) {
        // RPC aún no desplegada.
      }

      if (jugadores.isEmpty) {
        try {
          final linkRows = await _client
              .from('organizador_jugadores')
              .select('jugador_id')
              .eq('organizador_id', uid);
          final ids = <String>[];
          for (final raw in linkRows as List) {
            final id = (raw as Map)['jugador_id']?.toString();
            if (id != null && id.isNotEmpty) ids.add(id);
          }
          if (ids.isNotEmpty) {
            var profileQuery =
                _client.from('profiles').select().inFilter('id', ids);
            if (soloActivos == true) {
              profileQuery = profileQuery.eq('activo', true);
            }
            final profiles = await profileQuery;
            for (final raw in profiles as List) {
              final jugador = Jugador.fromSupabaseMap(
                Map<String, dynamic>.from(raw as Map),
              );
              final id = jugador.supabaseId;
              if (id != null) seen.add(id);
              jugadores.add(jugador);
            }
          }
        } catch (_) {
          // Sin roster todavía.
        }
      }

      // Incluir al organizador (también juega / aparece en roster y convocatorias).
      if (incluirUsuarioActual && !seen.contains(uid)) {
        final yo = await getById(uid);
        if (yo != null && (soloActivos != true || yo.activo)) {
          jugadores.insert(0, yo);
        }
      }

      jugadores.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
      return jugadores;
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
        final uid = SupabaseHelpers.currentUserId;
        final jid = actualizado.supabaseId;
        if (uid != null && jid != null) {
          try {
            await _client.rpc(
              'vincular_jugador_organizador',
              params: {'p_jugador_id': jid, 'p_organizador_id': uid},
            );
          } catch (_) {}
        }
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
      final creado = Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
      final uid = SupabaseHelpers.currentUserId;
      final jid = creado.supabaseId;
      if (uid != null && jid != null) {
        try {
          await _client.rpc(
            'vincular_jugador_organizador',
            params: {'p_jugador_id': jid, 'p_organizador_id': uid},
          );
        } catch (_) {
          await _client.from('organizador_jugadores').upsert({
            'organizador_id': uid,
            'jugador_id': jid,
          });
        }
      }
      return creado;
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
      final uid = SupabaseHelpers.currentUserId;
      if (uid != null) {
        await _client
            .from('organizador_jugadores')
            .delete()
            .eq('organizador_id', uid)
            .eq('jugador_id', id);
      }
      // Si el perfil sigue vinculado a otros clubs o tiene auth, el DELETE
      // puede no aplicar; el unlink ya lo saca del roster de este organizador.
      try {
        await _client.from('profiles').delete().eq('id', id);
      } catch (_) {}
    });
    return 1;
  }
}
