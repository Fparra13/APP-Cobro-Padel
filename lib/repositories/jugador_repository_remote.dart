import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_helpers.dart';
import '../models/cuenta_saldo.dart';
import '../models/jugador.dart';

/// Repositorio de jugadores contra Supabase (`profiles` + cuentas
/// `organizador_jugadores.saldo_acumulado`).
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
      // Incluye oj.saldo_acumulado de la cuenta con este organizador.
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
          var linkQuery = _client
              .from('organizador_jugadores')
              .select('jugador_id, saldo_acumulado')
              .eq('organizador_id', uid);
          if (soloActivos == true) {
            linkQuery = linkQuery.eq('activo', true);
          }
          final linkRows = await linkQuery;
          final saldoPorJugador = <String, double>{};
          final ids = <String>[];
          for (final raw in linkRows as List) {
            final map = Map<String, dynamic>.from(raw as Map);
            final id = map['jugador_id']?.toString();
            if (id == null || id.isEmpty) continue;
            ids.add(id);
            saldoPorJugador[id] =
                (map['saldo_acumulado'] as num?)?.toDouble() ?? 0;
          }
          if (ids.isNotEmpty) {
            var profileQuery =
                _client.from('profiles').select().inFilter('id', ids);
            if (soloActivos == true) {
              profileQuery = profileQuery.eq('activo', true);
            }
            final profiles = await profileQuery;
            for (final raw in profiles as List) {
              final base = Jugador.fromSupabaseMap(
                Map<String, dynamic>.from(raw as Map),
              );
              final id = base.supabaseId;
              if (id == null) continue;
              seen.add(id);
              jugadores.add(
                base.copyWith(saldoAcumulado: saldoPorJugador[id] ?? 0),
              );
            }
          }
        } catch (_) {
          // Sin roster todavía.
        }
      }

      // Incluir al organizador (también juega / aparece en roster y convocatorias).
      if (incluirUsuarioActual && !seen.contains(uid)) {
        final yo = await getById(uid, organizadorId: uid);
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

  /// Perfil + saldo de cuenta con [organizadorId] (default: org autenticado).
  ///
  /// Sin [organizadorId] ni sesión de org, [Jugador.saldoAcumulado] queda en 0
  /// (el saldo global en profiles ya no existe).
  Future<Jugador?> getById(String id, {String? organizadorId}) async {
    return SupabaseHelpers.guard('Obtener jugador', () async {
      final row =
          await _client.from('profiles').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      final base = Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
      final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
      if (orgId == null) return base;
      final saldo = await getSaldoCuenta(
        organizadorId: orgId,
        jugadorId: id,
      );
      return base.copyWith(saldoAcumulado: saldo);
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
      final base = Jugador.fromSupabaseMap(Map<String, dynamic>.from(row));
      final orgId = SupabaseHelpers.currentUserId;
      if (orgId == null) return base;
      final jid = base.supabaseId;
      if (jid == null) return base;
      final saldo = await getSaldoCuenta(
        organizadorId: orgId,
        jugadorId: jid,
      );
      return base.copyWith(saldoAcumulado: saldo);
    });
  }

  /// Saldo vivo de la cuenta jugador↔organizador (`organizador_jugadores`).
  Future<double> getSaldoCuenta({
    required String organizadorId,
    required String jugadorId,
  }) async {
    return SupabaseHelpers.guard('Obtener saldo cuenta', () async {
      final row = await _client
          .from('organizador_jugadores')
          .select('saldo_acumulado')
          .eq('organizador_id', organizadorId)
          .eq('jugador_id', jugadorId)
          .maybeSingle();
      if (row == null) return 0.0;
      return (row['saldo_acumulado'] as num?)?.toDouble() ?? 0.0;
    });
  }

  /// Cuentas del jugador autenticado con cada organizador (incluye créditos).
  Future<List<CuentaSaldo>> listarMisCuentasSaldo() async {
    return SupabaseHelpers.guard('Listar mis cuentas saldo', () async {
      try {
        final raw = await _client.rpc('get_mis_cuentas_saldo');
        final items = _asMapList(raw);
        if (items != null) {
          return items.map(CuentaSaldo.fromJson).toList();
        }
      } catch (_) {
        // Fallback abajo.
      }
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return [];
      final linkRows = await _client
          .from('organizador_jugadores')
          .select('organizador_id, saldo_acumulado, activo, left_at')
          .eq('jugador_id', uid);
      final orgIds = <String>[];
      final byOrg = <String, Map<String, dynamic>>{};
      for (final raw in linkRows as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        final oid = map['organizador_id']?.toString();
        if (oid == null || oid.isEmpty) continue;
        orgIds.add(oid);
        byOrg[oid] = map;
      }
      if (orgIds.isEmpty) return [];
      final profiles = await _client
          .from('profiles')
          .select('id, nombre, foto_url')
          .inFilter('id', orgIds);
      final out = <CuentaSaldo>[];
      for (final raw in profiles as List) {
        final pr = Map<String, dynamic>.from(raw as Map);
        final oid = pr['id']?.toString();
        if (oid == null) continue;
        final link = byOrg[oid];
        if (link == null) continue;
        out.add(
          CuentaSaldo.fromJson({
            'organizador_id': oid,
            'nombre': pr['nombre'],
            'foto_url': pr['foto_url'],
            'saldo_acumulado': link['saldo_acumulado'],
            'activo': link['activo'],
            'left_at': link['left_at'],
          }),
        );
      }
      out.sort(
        (a, b) => a.nombreOrganizador
            .toLowerCase()
            .compareTo(b.nombreOrganizador.toLowerCase()),
      );
      return out;
    });
  }

  List<Map<String, dynamic>>? _asMapList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return null;
  }

  /// Total home: solo suma deudas > 0. No netea créditos entre organizadores.
  Future<double> getMiTotalDeudaHome() async {
    return SupabaseHelpers.guard('Total deuda home', () async {
      try {
        final raw = await _client.rpc('get_mi_total_deuda_home');
        if (raw is num) return raw.toDouble();
        if (raw is String) return double.tryParse(raw) ?? 0;
        return 0;
      } catch (_) {
        final cuentas = await listarMisCuentasSaldo();
        var total = 0.0;
        for (final c in cuentas) {
          if (c.saldoAcumulado > 0.005) total += c.saldoAcumulado;
        }
        return total;
      }
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
      throw Exception('El participante debe tener un nombre');
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

    return SupabaseHelpers.write('Crear jugador', () async {
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
    await SupabaseHelpers.write('Actualizar jugador', () async {
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
    await SupabaseHelpers.write('Cambiar estado jugador', () async {
      await _client.from('profiles').update({'activo': activo}).eq('id', id);
    });
  }

  /// Recalcula el saldo de la cuenta org↔jugador desde `saldos_historicos`.
  ///
  /// [nuevoSaldo] se ignora (compat API): el SSOT se deriva del historial.
  Future<void> updateSaldo(
    String jugadorId,
    double nuevoSaldo, {
    String? organizadorId,
  }) async {
    // Mantener firma posicional para callers existentes; valor no se escribe.
    assert(nuevoSaldo.isFinite);
    await SupabaseHelpers.write('Actualizar saldo cuenta', () async {
      final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
      if (orgId == null) {
        throw Exception('updateSaldo: sin organizador autenticado');
      }
      await _client.rpc(
        'recalcular_saldo_cuenta',
        params: {
          'p_organizador_id': orgId,
          'p_jugador_id': jugadorId,
        },
      );
    });
  }

  /// Recalcula saldos de varias cuentas del organizador autenticado.
  /// Incluye al propio organizador si también asistió (fila de saldo dual).
  Future<void> recalcularSaldosBatch(
    List<String> jugadorIds, {
    String? organizadorId,
  }) async {
    final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
    final ids = jugadorIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    await SupabaseHelpers.write('Recalcular saldos cuentas batch', () async {
      if (orgId == null) {
        throw Exception('recalcularSaldosBatch: sin organizador autenticado');
      }
      try {
        await _client.rpc(
          'recalcular_saldos_cuentas',
          params: {
            'p_organizador_id': orgId,
            'p_jugador_ids': ids,
          },
        );
        return;
      } catch (_) {
        // Fallback: uno a uno.
      }
      for (final id in ids) {
        await updateSaldo(id, 0, organizadorId: orgId);
      }
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

  /// Soft-leave del roster: conserva saldo de la cuenta (no hard-delete oj).
  Future<int> delete(String id) async {
    await SupabaseHelpers.write('Salir jugador del roster', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return;
      try {
        await _client.rpc(
          'bloquear_salida_cuenta_si_necesario',
          params: {
            'p_organizador_id': uid,
            'p_jugador_id': id,
          },
        );
        return;
      } catch (_) {
        // Fallback si RPC no está.
      }
      await _client
          .from('organizador_jugadores')
          .update({
            'activo': false,
            'left_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('organizador_id', uid)
          .eq('jugador_id', id);
    });
    return 1;
  }
}
