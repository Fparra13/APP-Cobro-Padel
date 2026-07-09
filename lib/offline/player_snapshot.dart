import '../models/deuda_partido_anterior.dart';
import '../models/estadisticas_jugador.dart';
import '../models/jugador.dart';
import '../models/detalle_partido.dart';
import '../models/mi_convocatoria.dart';
import '../models/saldo_historico.dart';
import 'offline_snapshot_codec.dart';

/// Clave de snapshot para [PlayerHomeScreen].
const playerHomeSnapshotKey = 'player_home';

String playerJugadorFichaSnapshotKey(String jugadorKey) =>
    'player_jugador_ficha_$jugadorKey';

class PlayerHomeData {
  final List<MiConvocatoria> convocatorias;
  final List<DetallePartido> deudas;
  final Jugador? perfil;
  final EstadisticasJugador? misStats;
  final List<DetallePartido> partidosJugados;
  final List<SaldoHistorico> historialSaldo;
  final Map<int, double> saldosPorPartido;

  const PlayerHomeData({
    required this.convocatorias,
    required this.deudas,
    required this.perfil,
    required this.misStats,
    required this.partidosJugados,
    required this.historialSaldo,
    required this.saldosPorPartido,
  });

  Map<String, dynamic> toJson() => {
        'convocatorias': convocatorias.map(miConvocatoriaToJson).toList(),
        'deudas': deudas.map(detallePartidoToJson).toList(),
        'perfil':
            perfil != null ? jugadorToSnapshotJson(perfil!) : null,
        'misStats':
            misStats != null ? estadisticasJugadorToJson(misStats!) : null,
        'partidosJugados': partidosJugados.map(detallePartidoToJson).toList(),
        'historialSaldo': historialSaldo.map(saldoHistoricoToJson).toList(),
        'saldosPorPartido': saldosPorPartido.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      };

  factory PlayerHomeData.fromJson(Map<String, dynamic> json) {
    final saldosRaw = json['saldosPorPartido'] as Map? ?? const {};
    return PlayerHomeData(
      convocatorias: (json['convocatorias'] as List? ?? const [])
          .map((e) => miConvocatoriaFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      deudas: (json['deudas'] as List? ?? const [])
          .map((e) => detallePartidoFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      perfil: json['perfil'] != null
          ? jugadorFromSnapshotJson(
              Map<String, dynamic>.from(json['perfil'] as Map),
            )
          : null,
      misStats: json['misStats'] != null
          ? estadisticasJugadorFromJson(
              Map<String, dynamic>.from(json['misStats'] as Map),
            )
          : null,
      partidosJugados: (json['partidosJugados'] as List? ?? const [])
          .map((e) => detallePartidoFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      historialSaldo: (json['historialSaldo'] as List? ?? const [])
          .map((e) => saldoHistoricoFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      saldosPorPartido: saldosRaw.map(
        (k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble()),
      ),
    );
  }
}

class PlayerJugadorFichaData {
  final Jugador jugador;
  final List<SaldoHistorico> historial;
  final List<DeudaPartidoAnterior> pendientes;
  final int partidosJugados;
  final int partidosPagados;

  const PlayerJugadorFichaData({
    required this.jugador,
    required this.historial,
    required this.pendientes,
    required this.partidosJugados,
    required this.partidosPagados,
  });

  Map<String, dynamic> toJson() => {
        'jugador': jugadorToSnapshotJson(jugador),
        'historial': historial.map(saldoHistoricoToJson).toList(),
        'pendientes': pendientes.map(deudaPartidoAnteriorToJson).toList(),
        'partidosJugados': partidosJugados,
        'partidosPagados': partidosPagados,
      };

  factory PlayerJugadorFichaData.fromJson(Map<String, dynamic> json) =>
      PlayerJugadorFichaData(
        jugador: jugadorFromSnapshotJson(
          Map<String, dynamic>.from(json['jugador'] as Map),
        ),
        historial: (json['historial'] as List? ?? const [])
            .map((e) => saldoHistoricoFromJson(Map<String, dynamic>.from(e)))
            .toList(),
        pendientes: (json['pendientes'] as List? ?? const [])
            .map(
              (e) => deudaPartidoAnteriorFromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(),
        partidosJugados: (json['partidosJugados'] as num?)?.toInt() ?? 0,
        partidosPagados: (json['partidosPagados'] as num?)?.toInt() ?? 0,
      );
}
