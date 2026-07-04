import '../core/supabase_helpers.dart';
import '../core/supabase_parse.dart';
import '../models/saldo_historico.dart';

class SaldoRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<List<SaldoHistorico>> getByPartido(int partidoId) async {
    return SupabaseHelpers.guard('Historial saldo partido', () async {
      final rows = await _client
          .from('saldos_historicos')
          .select('*, profiles:jugador_id(nombre)')
          .eq('partido_id', partidoId)
          .order('fecha', ascending: true);

      return (rows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        map['nombre_jugador'] =
            SupabaseParse.nombrePerfilEmbed(map['profiles']);
        return SaldoHistorico.fromSupabaseMap(map);
      }).toList()
        ..sort(
          (a, b) => (a.nombreJugador ?? '').toLowerCase().compareTo(
                (b.nombreJugador ?? '').toLowerCase(),
              ),
        );
    });
  }

  Future<List<SaldoHistorico>> getByJugador(String jugadorId) async {
    return SupabaseHelpers.guard('Historial saldo jugador', () async {
      final rows = await _client
          .from('saldos_historicos')
          .select('*, profiles:jugador_id(nombre)')
          .eq('jugador_id', jugadorId)
          .order('fecha', ascending: false);

      return (rows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        map['nombre_jugador'] =
            SupabaseParse.nombrePerfilEmbed(map['profiles']);
        return SaldoHistorico.fromSupabaseMap(map);
      }).toList();
    });
  }
}
