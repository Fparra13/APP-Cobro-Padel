import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/detalle_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/jugador.dart';
import '../models/cuenta_saldo.dart';
import '../models/mi_convocatoria.dart';
import '../models/saldo_historico.dart';
import '../domain/player_home_stats.dart';
import '../widgets/desglose_cobro_panel.dart' show ordenarDeudasPorFecha;
import 'offline_screen_loader.dart';
import 'offline_snapshot_store.dart';
import 'player_snapshot.dart';

export 'player_snapshot.dart';
export 'offline_screen_loader.dart' show OfflineScreenLoadSource, OfflineScreenLoadResult;
export 'organizer_home_loader.dart' show offlineSnapshotStoreForCurrentUser;

Future<OfflineScreenLoadResult<PlayerHomeData>> loadPlayerHome({
  AppRepositories? repos,
  required OfflineSnapshotStore? snapshotStore,
  Future<PlayerHomeData> Function()? fetchOverride,
}) {
  assert(
    fetchOverride != null || repos != null,
    'repos requerido cuando no hay fetchOverride',
  );
  return loadWithOfflineSnapshot(
    snapshotKey: playerHomeSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () =>
        fetchOverride != null ? fetchOverride() : _fetchPlayerHome(repos!),
    encode: (data) => data.toJson(),
    decode: PlayerHomeData.fromJson,
  );
}

Future<OfflineScreenLoadResult<PlayerJugadorFichaData>> loadPlayerJugadorFicha({
  AppRepositories? repos,
  required String jugadorKey,
  required OfflineSnapshotStore? snapshotStore,
  Future<PlayerJugadorFichaData> Function()? fetchOverride,
}) {
  assert(
    fetchOverride != null || repos != null,
    'repos requerido cuando no hay fetchOverride',
  );
  return loadWithOfflineSnapshot(
    snapshotKey: playerJugadorFichaSnapshotKey(jugadorKey),
    snapshotStore: snapshotStore,
    fetch: () => fetchOverride != null
        ? fetchOverride()
        : _fetchPlayerJugadorFicha(repos!, jugadorKey),
    encode: (data) => data.toJson(),
    decode: PlayerJugadorFichaData.fromJson,
  );
}

Future<PlayerHomeData> _fetchPlayerHome(AppRepositories repos) async {
  final uid = AuthService.instance.currentUser?.id;
  final results = await Future.wait([
    repos.getMisConvocatoriasComoJugador(),
    repos.getMisDeudasPendientes(reconciliar: false),
    if (uid != null) repos.getJugador(uid) else Future<Jugador?>.value(null),
    repos.getMisPartidosJugados(limit: 20),
    if (uid != null)
      repos.getSaldosByJugador(uid)
    else
      Future<List<SaldoHistorico>>.value([]),
    repos.countMisConfirmaciones(),
    repos.listarMisCuentasSaldo(),
    repos.getMiTotalDeudaHome(),
  ]);

  List<EstadisticasJugador> statsAll = const [];
  if (AuthService.instance.isOrganizer) {
    try {
      statsAll = await repos.getEstadisticas();
    } catch (_) {
      // Estadísticas globales son opcionales; no bloquean el home del jugador.
    }
  }

  final convocatorias = results[0] as List<MiConvocatoria>;
  final deudas = ordenarDeudasPorFecha(results[1] as List<DetallePartido>);
  final perfil = results[2] as Jugador?;
  final partidosJugados = results[3] as List<DetallePartido>;
  final confirmacionesHistoricas = results[5] as int;
  final cuentasSaldo = results[6] as List<CuentaSaldo>;
  final totalDeudaHome = results[7] as double;
  final partidoIds = {
    ...deudas.map((d) => d.partidoId),
    ...partidosJugados.map((p) => p.partidoId),
  };

  Map<int, double> saldosPorPartido = const {};
  try {
    saldosPorPartido =
        await repos.getMisSaldosAnterioresPartidos(partidoIds);
  } catch (_) {}

  EstadisticasJugador? mine = buildMisEstadisticasDesdeHome(
    uid: uid,
    perfil: perfil,
    partidosJugados: partidosJugados,
    convocatorias: convocatorias,
    confirmacionesHistoricas: confirmacionesHistoricas,
    totalDeudaHome: totalDeudaHome,
  );
  if (mine == null && uid != null) {
    for (final s in statsAll) {
      if (s.jugadorKeyId == uid) {
        mine = s;
        break;
      }
    }
  }

  return PlayerHomeData(
    convocatorias: convocatorias,
    deudas: deudas,
    perfil: perfil,
    misStats: mine,
    partidosJugados: partidosJugados,
    historialSaldo: results[4] as List<SaldoHistorico>,
    saldosPorPartido: saldosPorPartido,
    cuentasSaldo: cuentasSaldo,
    totalDeudaHome: totalDeudaHome,
  );
}

Future<PlayerJugadorFichaData> _fetchPlayerJugadorFicha(
  AppRepositories repos,
  String jugadorKey,
) async {
  // Vista organizador: saldo e historial de la cuenta con auth.uid().
  final orgId = AuthService.instance.currentUser?.id;
  final data = await Future.wait([
    repos.getJugador(jugadorKey, organizadorId: orgId),
    repos.getSaldosByJugador(jugadorKey, organizadorId: orgId),
    repos.getPartidosPendientesJugador(jugadorKey),
    repos.getResumenPartidosJugador(jugadorKey),
  ]);

  final jugador = data[0] as Jugador?;
  if (jugador == null) {
    throw Exception(
      'Jugador no encontrado (id: $jugadorKey). '
      'Puede estar bloqueado por RLS en Supabase.',
    );
  }

  final resumen = data[3] as ({
    int partidosJugados,
    int partidosPagados,
    int partidosImpagos,
  });

  return PlayerJugadorFichaData(
    jugador: jugador,
    historial: data[1] as List<SaldoHistorico>,
    pendientes: data[2] as List<DeudaPartidoAnterior>,
    partidosJugados: resumen.partidosJugados,
    partidosPagados: resumen.partidosPagados,
  );
}
