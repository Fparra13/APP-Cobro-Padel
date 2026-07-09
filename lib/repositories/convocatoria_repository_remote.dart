import 'package:flutter/foundation.dart';

import '../domain/cobro_logic.dart';
import '../core/sport_type.dart';
import '../core/supabase_helpers.dart';
import '../core/supabase_parse.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../services/convocatoria_notificacion_service.dart';
import 'partido_repository_remote.dart';

/// Convocatorias contra Supabase.
class ConvocatoriaRepositoryRemote {
  final _client = SupabaseHelpers.client;
  final _notificaciones = ConvocatoriaNotificacionService();
  final _partidoRepo = PartidoRepositoryRemote();

  Future<List<ConvocatoriaCompleta>> getActivas() async {
    return SupabaseHelpers.guard('Listar convocatorias activas', () async {
      final rows = await _client
          .from('partidos')
          .select()
          .inFilter('estado', [
            EstadoPartido.organizando.dbValue,
            EstadoPartido.confirmado.dbValue,
          ])
          .order('fecha', ascending: true);

      final result = <ConvocatoriaCompleta>[];
      for (final row in rows as List) {
        final partidoId = (row['id'] as num).toInt();
        final conv = await getCompleta(partidoId);
        if (conv != null) result.add(conv);
      }
      return result;
    });
  }

  Future<ConvocatoriaCompleta?> getCompleta(int partidoId) async {
    return SupabaseHelpers.guard('Obtener convocatoria', () async {
      final partidoRow = await _client
          .from('partidos')
          .select()
          .eq('id', partidoId)
          .maybeSingle();
      if (partidoRow == null) return null;

      final partido = Partido.fromSupabaseMap(
        Map<String, dynamic>.from(partidoRow),
      );
      if (!partido.esConvocatoriaPendiente) return null;

      final convRows = await _client
          .from('convocatoria_jugadores')
          .select('*, profiles:jugador_id(*)')
          .eq('partido_id', partidoId)
          .order('es_suplente', ascending: true)
          .order('orden_espera', ascending: true);

      final jugadores = (convRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final profileMap = SupabaseParse.mapEmbed(map['profiles']);
        final jugador = profileMap != null
            ? Jugador.fromSupabaseMap(profileMap)
            : Jugador(
                supabaseId: map['jugador_id']?.toString(),
                nombre: 'Jugador',
                createdAt: DateTime.now(),
              );
        return ConvocatoriaJugadorEntry.fromSupabaseRow(
          map,
          jugador,
          partidoId,
        );
      }).toList()
        ..sort((a, b) {
          if (a.esSuplente != b.esSuplente) {
            return a.esSuplente ? 1 : -1;
          }
          if (a.esSuplente) {
            return (a.ordenEspera ?? 999).compareTo(b.ordenEspera ?? 999);
          }
          return a.jugador.nombre
              .toLowerCase()
              .compareTo(b.jugador.nombre.toLowerCase());
        });

      return ConvocatoriaCompleta(partido: partido, jugadores: jugadores);
    });
  }

  /// Roster completo para jugadores invitados (RLS solo devuelve la fila propia).
  Future<ConvocatoriaCompleta?> getRosterParaJugador({
    required int partidoId,
    required Partido partido,
  }) async {
    return SupabaseHelpers.guard('Roster convocatoria jugador', () async {
      try {
        final raw = await _client.rpc(
          'get_convocatoria_roster_jugador',
          params: {'p_partido_id': partidoId},
        );
        if (raw == null) return null;
        final map = Map<String, dynamic>.from(raw as Map);
        final titularesJson = map['titulares'];
        if (titularesJson is! List) return null;

        final jugadores = titularesJson.map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          final jugador = Jugador(
            supabaseId: row['jugador_id']?.toString(),
            nombre: row['nombre'] as String? ?? 'Jugador',
            fotoUrl: row['foto_url'] as String?,
            createdAt: DateTime.now(),
          );
          return ConvocatoriaJugadorEntry(
            partidoId: partidoId,
            jugador: jugador,
            estado: EstadoConfirmacion.fromDb(
              row['estado_confirmacion'] as String?,
            ),
            esSuplente: row['es_suplente'] as bool? ?? false,
          );
        }).toList();

        return ConvocatoriaCompleta(partido: partido, jugadores: jugadores);
      } catch (_) {
        return null;
      }
    });
  }

  Map<String, dynamic> _rowForInput(
    ConvocatoriaJugadorInput input,
    int horasLimite, {
    bool conTiempoLimite = false,
    String? tiempoLimitePreservado,
    bool? notificadoVencimientoPreservado,
  }) {
    String? tiempoLimite;
    if (tiempoLimitePreservado != null && tiempoLimitePreservado.isNotEmpty) {
      tiempoLimite = tiempoLimitePreservado;
    } else if (conTiempoLimite &&
        !input.esSuplente &&
        input.estado == EstadoConfirmacion.invitado) {
      tiempoLimite = SupabaseParse.toTimestamptz(
        DateTime.now().add(Duration(hours: horasLimite)),
      );
    }
    return {
      'jugador_id': input.jugadorId,
      'estado_confirmacion': input.estado.dbValue,
      'es_suplente': input.esSuplente,
      'orden_espera': input.ordenEspera,
      'tiempo_limite': tiempoLimite,
      'notificado_vencimiento': notificadoVencimientoPreservado ?? false,
      'recordatorio_plazo_enviado': false,
    };
  }

  EstadoConfirmacion _estadoTrasEdicion({
    EstadoConfirmacion? prevEstado,
    required EstadoConfirmacion inputEstado,
  }) =>
      CobroLogic.estadoTrasEdicionConvocatoria(
        prevEstado: prevEstado,
        inputEstado: inputEstado,
      );

  /// Prioriza el perfil con login (auth) si el organizador invita un pre-registro.
  Future<String> _resolveJugadorIdForConvocatoria(String jugadorId) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('email, telefono')
          .eq('id', jugadorId)
          .maybeSingle();
      if (profile == null) return jugadorId;

      final map = Map<String, dynamic>.from(profile);
      final email = SupabaseParse.toStringOrNull(map['email']) ??
          SupabaseParse.toStringOrNull(map['telefono']);
      if (email == null || !email.contains('@')) return jugadorId;

      final resolved = await _client.rpc(
        'resolve_profile_id_for_email',
        params: {'p_email': email},
      );
      final id = resolved?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {
      // RPC no desplegado: usar id original.
    }
    return jugadorId;
  }

  Future<int> invitar({
    required int partidoId,
    required ConvocatoriaJugadorInput input,
    required int horasLimite,
  }) async {
    return SupabaseHelpers.guard('Invitar jugador', () async {
      final jugadorId = await _resolveJugadorIdForConvocatoria(input.jugadorId);
      final resolvedInput = ConvocatoriaJugadorInput(
        jugadorId: jugadorId,
        esSuplente: input.esSuplente,
        ordenEspera: input.ordenEspera,
        estado: input.estado,
      );
      final row = await _client
          .from('convocatoria_jugadores')
          .insert({
            'partido_id': partidoId,
            ..._rowForInput(resolvedInput, horasLimite),
          })
          .select('id')
          .single();
      return (row['id'] as num).toInt();
    });
  }

  Future<void> actualizarConfirmacion({
    required int partidoId,
    required String jugadorId,
    required EstadoConfirmacion estado,
  }) async {
    await SupabaseHelpers.guard('Actualizar confirmación', () async {
      await _client.from('convocatoria_jugadores').update({
        'estado_confirmacion': estado.dbValue,
      }).eq('partido_id', partidoId).eq('jugador_id', jugadorId);
    });
  }

  Future<void> marcarNoRespondio({
    required int partidoId,
    required String jugadorId,
    bool notificadoVencimiento = false,
  }) async {
    await SupabaseHelpers.guard('Marcar no respondió', () async {
      await _client.from('convocatoria_jugadores').update({
        'estado_confirmacion': EstadoConfirmacion.noRespondio.dbValue,
        'notificado_vencimiento': notificadoVencimiento,
      }).eq('partido_id', partidoId).eq('jugador_id', jugadorId);
    });
  }

  Future<void> marcarRecordatorioPlazoEnviado({
    required int partidoId,
    required String jugadorId,
  }) async {
    await SupabaseHelpers.guard('Marcar recordatorio plazo', () async {
      try {
        await _client.from('convocatoria_jugadores').update({
          'recordatorio_plazo_enviado': true,
        }).eq('partido_id', partidoId).eq('jugador_id', jugadorId);
      } catch (_) {
        // Columna aún no migrada en remoto.
      }
    });
  }

  Future<Jugador?> promoverSiguienteSuplente(int partidoId) async {
    return SupabaseHelpers.guard('Promover suplente', () async {
      final conv = await getCompleta(partidoId);
      if (conv == null) return null;
      final ocupados = conv.titulares
          .where((t) => t.estado.esTitularActivo)
          .length;
      if (ocupados >= conv.partido.cuposMax) return null;
      if (conv.suplentes.isEmpty) return null;

      final suplente = conv.suplentes.first;
      final jugadorId = suplente.jugador.keyId;
      if (jugadorId.isEmpty) return null;

      final limite = DateTime.now().add(
        Duration(hours: conv.partido.horasLimiteRespuesta),
      );
      await _client.from('convocatoria_jugadores').update({
        'es_suplente': false,
        'orden_espera': null,
        'estado_confirmacion': EstadoConfirmacion.invitado.dbValue,
        'tiempo_limite': SupabaseParse.toTimestamptz(limite),
        'notificado_vencimiento': false,
        'recordatorio_plazo_enviado': false,
      }).eq('partido_id', partidoId).eq('jugador_id', jugadorId);

      return suplente.jugador;
    });
  }

  Future<int> crear({
    required DateTime fecha,
    String? recinto,
    int? recintoId,
    String? recintoMapsUrl,
    double? recintoLat,
    double? recintoLng,
    String? notas,
    int cuposMax = 4,
    int horasLimiteRespuesta = 24,
    required List<ConvocatoriaJugadorInput> jugadores,
    String? organizadorId,
    SportType? sportType,
  }) async {
    return SupabaseHelpers.guard('Crear convocatoria', () async {
      final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
      final sport = sportType ?? SportType.padel;
      final partidoRow = await _client
          .from('partidos')
          .insert({
            'fecha': SupabaseParse.toTimestamptz(fecha),
            'recinto': recinto,
            'recinto_id': recintoId,
            'recinto_maps_url': recintoMapsUrl,
            'recinto_lat': recintoLat,
            'recinto_lng': recintoLng,
            'notas': notas,
            'estado': EstadoPartido.organizando.dbValue,
            'cupos_max': cuposMax,
            'horas_limite_respuesta': horasLimiteRespuesta,
            'sport_type': sport.dbValue,
            if (orgId != null) 'organizador_id': orgId,
          })
          .select('id')
          .single();

      final partidoId = (partidoRow['id'] as num).toInt();
      for (final input in jugadores) {
        await invitar(
          partidoId: partidoId,
          input: input,
          horasLimite: horasLimiteRespuesta,
        );
      }
      return partidoId;
    });
  }

  Future<void> activarTiemposLimiteConvocatoria({
    required int partidoId,
    required int horasLimite,
  }) async {
    await SupabaseHelpers.guard('Activar tiempos límite', () async {
      final limite = SupabaseParse.toTimestamptz(
        DateTime.now().add(Duration(hours: horasLimite)),
      );
      await _client
          .from('convocatoria_jugadores')
          .update({'tiempo_limite': limite})
          .eq('partido_id', partidoId)
          .eq('es_suplente', false)
          .eq('estado_confirmacion', EstadoConfirmacion.invitado.dbValue);
    });
  }

  Future<void> marcarConfirmado(int partidoId) async {
    await SupabaseHelpers.guard('Confirmar partido', () async {
      await _client.from('partidos').update({
        'estado': EstadoPartido.confirmado.dbValue,
      }).eq('id', partidoId);
    });
  }

  /// Vuelve a `organizando` si faltan confirmados (p. ej. titular se bajó).
  Future<void> reabrirConvocatoriaOrganizador(int partidoId) async {
    await SupabaseHelpers.guard('Reabrir convocatoria', () async {
      await _client.from('partidos').update({
        'estado': EstadoPartido.organizando.dbValue,
      }).eq('id', partidoId);
    });
  }

  Future<void> actualizarOrdenListaEspera({
    required int partidoId,
    required List<String> jugadorIdsEnOrden,
  }) async {
    await SupabaseHelpers.guard('Orden lista de espera', () async {
      for (var i = 0; i < jugadorIdsEnOrden.length; i++) {
        final id = jugadorIdsEnOrden[i];
        if (id.isEmpty) continue;
        await _client.from('convocatoria_jugadores').update({
          'orden_espera': i + 1,
        }).eq('partido_id', partidoId).eq('jugador_id', id);
      }
    });
  }

  Future<void> eliminar(int partidoId) async {
    await _partidoRepo.eliminarPartido(partidoId);
  }

  Future<void> cancelar(int partidoId) async {
    await SupabaseHelpers.guard('Cancelar convocatoria', () async {
      try {
        await _client.rpc(
          'cancelar_convocatoria_organizador',
          params: {'p_partido_id': partidoId},
        );
        return;
      } catch (_) {
        // RPC no desplegado: fallback manual.
      }

      await _client.from('partidos').update({
        'estado': EstadoPartido.cancelado.dbValue,
        'resuelto_en': SupabaseParse.toTimestamptz(DateTime.now()),
      }).eq('id', partidoId);

      await _client
          .from('convocatoria_jugadores')
          .delete()
          .eq('partido_id', partidoId);
    });
  }

  Future<void> reprogramar({
    required int partidoId,
    required DateTime nuevaFecha,
  }) async {
    await SupabaseHelpers.guard('Reprogramar convocatoria', () async {
      try {
        await _client.rpc(
          'reprogramar_convocatoria_organizador',
          params: {
            'p_partido_id': partidoId,
            'p_nueva_fecha': SupabaseParse.toTimestamptz(nuevaFecha),
          },
        );
        return;
      } catch (_) {
        // RPC no desplegado: fallback manual.
      }

      final conv = await getCompleta(partidoId);
      if (conv == null) {
        throw Exception('Convocatoria no encontrada');
      }

      final limite = DateTime.now().add(
        Duration(hours: conv.partido.horasLimiteRespuesta),
      );

      await _client.from('partidos').update({
        'fecha': SupabaseParse.toTimestamptz(nuevaFecha),
        'estado': EstadoPartido.organizando.dbValue,
        'resuelto_en': null,
      }).eq('id', partidoId);

      await _client
          .from('convocatoria_jugadores')
          .update({
            'tiempo_limite': SupabaseParse.toTimestamptz(limite),
            'notificado_vencimiento': false,
            'recordatorio_plazo_enviado': false,
          })
          .eq('partido_id', partidoId)
          .eq('es_suplente', false)
          .eq('estado_confirmacion', EstadoConfirmacion.invitado.dbValue);
    });
  }

  Future<void> actualizar({
    required int partidoId,
    required DateTime fecha,
    String? recinto,
    int? recintoId,
    String? recintoMapsUrl,
    double? recintoLat,
    double? recintoLng,
    String? notas,
    required int cuposMax,
    required int horasLimiteRespuesta,
    required List<ConvocatoriaJugadorInput> jugadores,
    SportType? sportType,
  }) async {
    await SupabaseHelpers.guard('Actualizar convocatoria', () async {
      final prevRows = await _client
          .from('convocatoria_jugadores')
          .select()
          .eq('partido_id', partidoId);

      final snapshot = <String, Map<String, dynamic>>{};
      for (final row in prevRows as List) {
        final jid = row['jugador_id']?.toString();
        if (jid != null && jid.isNotEmpty) {
          snapshot[jid] = Map<String, dynamic>.from(row);
        }
      }

      await _client.from('partidos').update({
        'fecha': SupabaseParse.toTimestamptz(fecha),
        'recinto': recinto,
        'recinto_id': recintoId,
        'recinto_maps_url': recintoMapsUrl,
        'recinto_lat': recintoLat,
        'recinto_lng': recintoLng,
        'notas': notas,
        'cupos_max': cuposMax,
        'horas_limite_respuesta': horasLimiteRespuesta,
        if (sportType != null) 'sport_type': sportType.dbValue,
      }).eq('id', partidoId);

      await _client
          .from('convocatoria_jugadores')
          .delete()
          .eq('partido_id', partidoId);

      for (final input in jugadores) {
        final resolvedId =
            await _resolveJugadorIdForConvocatoria(input.jugadorId);
        final prev = snapshot[resolvedId] ?? snapshot[input.jugadorId];
        final prevEstado = prev == null
            ? null
            : EstadoConfirmacion.fromDb(
                prev['estado_confirmacion'] as String?,
              );
        final estado = _estadoTrasEdicion(
          prevEstado: prevEstado,
          inputEstado: input.estado,
        );
        final conservarPlazo = estado == EstadoConfirmacion.invitado;

        await _client.from('convocatoria_jugadores').insert({
          'partido_id': partidoId,
          ..._rowForInput(
            ConvocatoriaJugadorInput(
              jugadorId: resolvedId,
              esSuplente: input.esSuplente,
              ordenEspera: input.ordenEspera,
              estado: estado,
            ),
            horasLimiteRespuesta,
            tiempoLimitePreservado: conservarPlazo && prev != null
                ? prev['tiempo_limite']?.toString()
                : null,
            notificadoVencimientoPreservado: conservarPlazo && prev != null
                ? prev['notificado_vencimiento'] as bool?
                : false,
          ),
        });
      }
    });
  }

  Future<void> aplicarConfirmaciones({
    required int partidoId,
    required Map<String, EstadoConfirmacion> cambios,
  }) async {
    for (final entry in cambios.entries) {
      await actualizarConfirmacion(
        partidoId: partidoId,
        jugadorId: entry.key,
        estado: entry.value,
      );
    }
  }

  Future<List<ConvocatoriaJugadorEntry>> getMisConvocatoriasPendientes() async {
    final todas = await getMisConvocatoriasComoJugador();
    return todas
        .where((m) => m.requiereRespuesta)
        .map((m) => m.entry)
        .toList();
  }

  MiConvocatoria? _miConvocatoriaFromRpcMap(
    Map<String, dynamic> map,
    String uid, {
    bool soloPendientes = true,
  }) {
    final partidoMap = SupabaseParse.mapEmbed(map['partidos']);
    if (partidoMap == null) return null;

    final partido = Partido.fromSupabaseMap(partidoMap);
    if (soloPendientes && !partido.esConvocatoriaPendiente) return null;

    final resolvedPartidoId =
        partido.id ?? SupabaseParse.toInt(map['partido_id']);
    final jugador = Jugador(
      supabaseId: map['jugador_id']?.toString() ?? uid,
      nombre: 'Yo',
      createdAt: DateTime.now(),
    );
    final entry = ConvocatoriaJugadorEntry.fromSupabaseRow(
      map,
      jugador,
      resolvedPartidoId,
    );
    return MiConvocatoria(entry: entry, partido: partido);
  }

  Future<List<MiConvocatoria>> getMisConvocatoriasComoJugador() async {
    return SupabaseHelpers.guard('Mis convocatorias', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) return [];

      try {
        final raw = await _client.rpc('get_mis_convocatorias_jugador');
        if (raw is List) {
          final result = <MiConvocatoria>[];
          for (final item in raw) {
            if (item is! Map) continue;
            final conv = _miConvocatoriaFromRpcMap(
              Map<String, dynamic>.from(item),
              uid,
            );
            if (conv != null) result.add(conv);
          }
          result.sort((a, b) => a.partido.fecha.compareTo(b.partido.fecha));
          return result;
        }
      } catch (_) {
        // Fallback a consulta directa si el RPC no está desplegado.
      }

      final rows = await _client
          .from('convocatoria_jugadores')
          .select('*, partidos!inner(*)')
          .eq('jugador_id', uid);

      final result = <MiConvocatoria>[];
      for (final raw in rows as List) {
        final conv = _miConvocatoriaFromRpcMap(
          Map<String, dynamic>.from(raw),
          uid,
        );
        if (conv != null) result.add(conv);
      }

      result.sort((a, b) => a.partido.fecha.compareTo(b.partido.fecha));
      return result;
    });
  }

  Future<MiConvocatoria?> getMiConvocatoria(int partidoId) async {
    final uid = SupabaseHelpers.currentUserId;
    if (uid == null) return null;

    return SupabaseHelpers.guard('Mi convocatoria', () async {
      try {
        final raw = await _client.rpc(
          'get_mi_convocatoria_jugador',
          params: {'p_partido_id': partidoId},
        );
        if (raw is Map) {
          return _miConvocatoriaFromRpcMap(
            Map<String, dynamic>.from(raw),
            uid,
            soloPendientes: false,
          );
        }
      } catch (_) {
        // Fallback a consulta directa.
      }

      final row = await _client
          .from('convocatoria_jugadores')
          .select('*, partidos!inner(*)')
          .eq('partido_id', partidoId)
          .eq('jugador_id', uid)
          .maybeSingle();
      if (row == null) return null;

      return _miConvocatoriaFromRpcMap(
        Map<String, dynamic>.from(row),
        uid,
        soloPendientes: false,
      );
    });
  }

  Future<void> responderConvocatoria({
    required int partidoId,
    required bool confirmo,
  }) async {
    await SupabaseHelpers.guard('Responder convocatoria', () async {
      final uid = SupabaseHelpers.currentUserId;
      if (uid == null) {
        throw Exception('Sesión requerida');
      }

      final estadoEsperado = confirmo
          ? EstadoConfirmacion.confirmado
          : EstadoConfirmacion.rechazado;

      try {
        await _client.rpc('relink_convocatorias_por_email');
      } catch (_) {}

      var actualizado = false;
      try {
        final ok = await _client.rpc(
          'actualizar_confirmacion_jugador',
          params: {
            'p_partido_id': partidoId,
            'p_confirmo': confirmo,
          },
        );
        actualizado = ok == true;
      } catch (_) {}

      if (!actualizado) {
        actualizado = await _actualizarConfirmacionVerificado(
          partidoId: partidoId,
          jugadorId: uid,
          estado: estadoEsperado,
        );
      }

      if (!actualizado) {
        final conv = await getMiConvocatoria(partidoId);
        final jugadorId = conv?.entry.jugador.keyId;
        if (jugadorId != null &&
            jugadorId.isNotEmpty &&
            jugadorId != uid) {
          actualizado = await _actualizarConfirmacionVerificado(
            partidoId: partidoId,
            jugadorId: jugadorId,
            estado: estadoEsperado,
          );
        }
      }

      if (!actualizado ||
          !await _verificarEstadoConfirmacion(
            partidoId: partidoId,
            estadoEsperado: estadoEsperado,
          )) {
        throw Exception(
          'No se pudo registrar tu respuesta. Reintenta en unos segundos.',
        );
      }

      try {
        final conv = await getMiConvocatoria(partidoId);
        final profile = await _client
            .from('profiles')
            .select('nombre')
            .eq('id', uid)
            .maybeSingle();
        final nombre = SupabaseParse.toStringOrNull(
              Map<String, dynamic>.from(profile ?? {})['nombre'],
            ) ??
            'Jugador';
        await _notificaciones.notificarRespuestaOrganizador(
          partidoId: partidoId,
          confirmo: confirmo,
          jugadorNombre: nombre,
          fechaPartido: conv?.partido.fecha,
        );
      } catch (e) {
        debugPrint('Notificación respuesta organizador: $e');
      }
    });
  }

  Future<bool> _actualizarConfirmacionVerificado({
    required int partidoId,
    required String jugadorId,
    required EstadoConfirmacion estado,
  }) async {
    final rows = await _client
        .from('convocatoria_jugadores')
        .update({'estado_confirmacion': estado.dbValue})
        .eq('partido_id', partidoId)
        .eq('jugador_id', jugadorId)
        .select('id');
    return (rows as List).isNotEmpty;
  }

  Future<bool> _verificarEstadoConfirmacion({
    required int partidoId,
    required EstadoConfirmacion estadoEsperado,
  }) async {
    try {
      await _client.rpc('relink_convocatorias_por_email');
    } catch (_) {}

    final conv = await getMiConvocatoria(partidoId);
    if (conv == null) return false;
    return conv.entry.estado == estadoEsperado;
  }

  Future<List<String>> getConfirmadosIds(int partidoId) async {
    return SupabaseHelpers.guard('Confirmados convocatoria', () async {
      final rows = await _client
          .from('convocatoria_jugadores')
          .select('jugador_id')
          .eq('partido_id', partidoId)
          .eq('es_suplente', false)
          .eq('estado_confirmacion', EstadoConfirmacion.confirmado.dbValue);
      return (rows as List).map((r) => r['jugador_id'] as String).toList();
    });
  }
}
