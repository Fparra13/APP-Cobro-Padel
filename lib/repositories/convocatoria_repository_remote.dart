import '../core/supabase_helpers.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../models/partido.dart';

/// Convocatorias contra Supabase.
class ConvocatoriaRepositoryRemote {
  final _client = SupabaseHelpers.client;

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
          .eq('partido_id', partidoId);

      final jugadores = (convRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final profile = Map<String, dynamic>.from(map['profiles'] as Map);
        final jugador = Jugador.fromSupabaseMap(profile);
        return ConvocatoriaJugadorEntry(
          id: (map['id'] as num?)?.toInt(),
          partidoId: partidoId,
          jugador: jugador,
          estado: EstadoConfirmacion.fromDb(
            map['estado_confirmacion'] as String?,
          ),
        );
      }).toList()
        ..sort(
          (a, b) => a.jugador.nombre.toLowerCase().compareTo(
                b.jugador.nombre.toLowerCase(),
              ),
        );

      return ConvocatoriaCompleta(partido: partido, jugadores: jugadores);
    });
  }

  Future<int> invitar({
    required int partidoId,
    required String jugadorId,
    EstadoConfirmacion estado = EstadoConfirmacion.invitado,
  }) async {
    return SupabaseHelpers.guard('Invitar jugador', () async {
      final row = await _client
          .from('convocatoria_jugadores')
          .insert({
            'partido_id': partidoId,
            'jugador_id': jugadorId,
            'estado_confirmacion': estado.dbValue,
          })
          .select('id')
          .single();
      return (row['id'] as num).toInt();
    });
  }

  Future<void> responderInvitacion({
    required int convocatoriaId,
    required EstadoConfirmacion estado,
  }) async {
    await SupabaseHelpers.guard('Responder invitación', () async {
      await _client.from('convocatoria_jugadores').update({
        'estado_confirmacion': estado.dbValue,
      }).eq('id', convocatoriaId);
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

  Future<int> crear({
    required DateTime fecha,
    String? recinto,
    String? notas,
    int cuposMax = 4,
    required List<String> jugadoresInvitados,
    String? organizadorId,
  }) async {
    return SupabaseHelpers.guard('Crear convocatoria', () async {
      final orgId = organizadorId ?? SupabaseHelpers.currentUserId;
      final partidoRow = await _client
          .from('partidos')
          .insert({
            'fecha': fecha.toIso8601String(),
            'recinto': recinto,
            'notas': notas,
            'estado': EstadoPartido.organizando.dbValue,
            'cupos_max': cuposMax,
            if (orgId != null) 'organizador_id': orgId,
          })
          .select('id')
          .single();

      final partidoId = (partidoRow['id'] as num).toInt();
      for (final jugadorId in jugadoresInvitados.toSet()) {
        await invitar(partidoId: partidoId, jugadorId: jugadorId);
      }
      return partidoId;
    });
  }

  Future<void> marcarConfirmado(int partidoId) async {
    await SupabaseHelpers.guard('Confirmar partido', () async {
      await _client.from('partidos').update({
        'estado': EstadoPartido.confirmado.dbValue,
      }).eq('id', partidoId);
    });
  }

  Future<void> eliminar(int partidoId) async {
    await SupabaseHelpers.guard('Eliminar convocatoria', () async {
      await _client.from('partidos').delete().eq('id', partidoId);
    });
  }
}
