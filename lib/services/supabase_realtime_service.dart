import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_repositories.dart';
import '../core/supabase_helpers.dart';

typedef RealtimeVoidCallback = void Function();

/// Suscripciones Realtime de Supabase para sincronización colaborativa.
class SupabaseRealtimeService {
  SupabaseRealtimeService._();
  static final SupabaseRealtimeService instance = SupabaseRealtimeService._();

  RealtimeChannel? _convocatoriaChannel;
  RealtimeChannel? _detallesChannel;
  RealtimeChannel? _globalChannel;
  Timer? _debounce;

  SupabaseClient get _client => SupabaseHelpers.client;

  void _debouncedNotify() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      AppRepositories.notifyDataChanged();
    });
  }

  /// Actualización automática en home admin/jugador.
  void subscribeAppRefresh() {
    if (_globalChannel != null) return;
    _globalChannel = _client
        .channel('app-global-refresh')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'detalles_partido',
          callback: (_) => _debouncedNotify(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'convocatoria_jugadores',
          callback: (_) => _debouncedNotify(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _debouncedNotify(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'partidos',
          callback: (_) => _debouncedNotify(),
        )
        .subscribe();
  }

  void unsubscribeAppRefresh() {
    _debounce?.cancel();
    final channel = _globalChannel;
    if (channel != null) {
      _client.removeChannel(channel);
      _globalChannel = null;
    }
  }

  /// Escucha cambios en convocatoria_jugadores y partidos de un partido.
  void subscribeConvocatoria({
    required int partidoId,
    required RealtimeVoidCallback onChange,
  }) {
    unsubscribeConvocatoria();
    final id = partidoId.toString();
    _convocatoriaChannel = _client
        .channel('convocatoria:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'convocatoria_jugadores',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'partido_id',
            value: id,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'partidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: id,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  void unsubscribeConvocatoria() {
    final channel = _convocatoriaChannel;
    if (channel != null) {
      _client.removeChannel(channel);
      _convocatoriaChannel = null;
    }
  }

  void subscribeDetallesPartido({
    required int partidoId,
    required RealtimeVoidCallback onChange,
  }) {
    unsubscribeDetallesPartido();
    final id = partidoId.toString();
    _detallesChannel = _client
        .channel('detalles:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'detalles_partido',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'partido_id',
            value: id,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  void unsubscribeDetallesPartido() {
    final channel = _detallesChannel;
    if (channel != null) {
      _client.removeChannel(channel);
      _detallesChannel = null;
    }
  }

  void disposeAll() {
    unsubscribeConvocatoria();
    unsubscribeDetallesPartido();
    unsubscribeAppRefresh();
  }
}
