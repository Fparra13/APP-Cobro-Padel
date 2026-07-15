import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../domain/organizer_cycle_logic.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/convocatoria_jugador.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../repositories/partido_repository.dart';
import '../widgets/desglose_cobro_panel.dart' show ordenarDeudasPorFecha;
import '../widgets/mis_invitaciones_panel.dart';
import 'offline_screen_loader.dart';
import 'offline_snapshot_store.dart';
import 'organizer_home_snapshot.dart';

export 'offline_screen_loader.dart' show OfflineScreenLoadSource, OfflineScreenLoadResult;

typedef OrganizerHomeLoadSource = OfflineScreenLoadSource;
typedef OrganizerHomeLoadResult = OfflineScreenLoadResult<OrganizerHomeData>;

Future<OrganizerHomeLoadResult> loadOrganizerHome({
  AppRepositories? repos,
  required OfflineSnapshotStore? snapshotStore,
  Future<OrganizerHomeData> Function()? fetchOverride,
}) async {
  assert(
    fetchOverride != null || repos != null,
    'repos requerido cuando no hay fetchOverride',
  );
  final result = await loadWithOfflineSnapshot(
    snapshotKey: organizerHomeSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () =>
        fetchOverride != null ? fetchOverride() : _fetchFromRepos(repos!),
    encode: (data) => data.toJson(),
    decode: OrganizerHomeData.fromJson,
  );
  // Inicio del organizador nunca debe quedar en pantalla de error genérica
  // (datos de prueba / ledger incompleto / RPC puntual). Preferir vacío vivo.
  if (result.source == OrganizerHomeLoadSource.error) {
    return const OrganizerHomeLoadResult(
      source: OrganizerHomeLoadSource.live,
      data: OrganizerHomeData.empty,
    );
  }
  return result;
}

Future<OfflineScreenLoadResult<OrganizerCobrosData>> loadOrganizerCobros({
  required AppRepositories repos,
  required OfflineSnapshotStore? snapshotStore,
}) {
  return loadWithOfflineSnapshot(
    snapshotKey: organizerCobrosSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () async {
      final resumenes = await _safeEmpty(
        () => repos.getResumenJugadores(reconciliar: false),
        <ResumenJugador>[],
      );
      return OrganizerCobrosData(resumenes: resumenes);
    },
    encode: (data) => data.toJson(),
    decode: OrganizerCobrosData.fromJson,
  );
}

Future<OfflineScreenLoadResult<OrganizerJugadoresData>> loadOrganizerJugadores({
  required AppRepositories repos,
  required OfflineSnapshotStore? snapshotStore,
}) {
  return loadWithOfflineSnapshot(
    snapshotKey: organizerJugadoresSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () async {
      final jugadores = await repos.getJugadores(incluirUsuarioActual: true);
      return OrganizerJugadoresData(jugadores: jugadores);
    },
    encode: (data) => data.toJson(),
    decode: OrganizerJugadoresData.fromJson,
  );
}

Future<OfflineScreenLoadResult<OrganizerHistorialPartidosData>>
    loadOrganizerHistorialPartidos({
  required AppRepositories repos,
  required OfflineSnapshotStore? snapshotStore,
}) {
  return loadWithOfflineSnapshot(
    snapshotKey: organizerHistorialPartidosSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () async {
      final results = await Future.wait([
        repos.getPartidosJugados(),
        repos.getConvocatoriasActivas(),
      ]);
      final list = results[0] as List<Partido>;
      final convocatorias = results[1] as List<ConvocatoriaCompleta>;
      final ids = list.map((p) => p.id).whereType<int>().toList();
      final completos = await repos.getPartidosCompletosListaResumen(ids);
      return OrganizerHistorialPartidosData(
        partidos: completos,
        convocatorias: convocatorias,
      );
    },
    encode: (data) => data.toJson(),
    decode: OrganizerHistorialPartidosData.fromJson,
  );
}

OfflineSnapshotStore? offlineSnapshotStoreForCurrentUser() {
  final userId = AuthService.instance.currentUser?.id;
  if (userId == null) return null;
  return OfflineSnapshotStore(userId: userId);
}

Future<T> _safeEmpty<T>(Future<T> Function() run, T fallback) async {
  try {
    return await run();
  } catch (_) {
    return fallback;
  }
}

Future<OrganizerHomeData> _fetchFromRepos(AppRepositories repos) async {
  try {
    // Cada bloque es independiente: un fallo (ledger incompleto, RPC, etc.)
    // no tumba todo el Inicio del organizador.
    final resumenes = await _safeEmpty(
      () => repos.getResumenJugadores(reconciliar: false),
      <ResumenJugador>[],
    );
    final convocatorias = await _safeEmpty(
      () => repos.getConvocatoriasActivas(),
      <ConvocatoriaCompleta>[],
    );
    final misInvitaciones = await _safeEmpty(
      () => MisInvitacionesPanel.cargarPendientes(repos),
      <MiConvocatoria>[],
    );
    final pagosPorValidar = repos.isCloud
        ? await _safeEmpty(
            () => repos.getPagosPorValidar(),
            <DetallePartido>[],
          )
        : <DetallePartido>[];
    final misDeudas = repos.isCloud
        ? await _safeEmpty(
            () => repos.getMisDeudasPendientes(),
            <DetallePartido>[],
          )
        : <DetallePartido>[];

    var partidos = <PartidoCompleto>[];
    var desglose = <DesgloseJugador>[];
    try {
      partidos = await repos.getPartidosJugadosRecientesResumen(limit: 8);
      final id = partidos.isEmpty ? null : partidos.first.partido.id;
      if (id != null) {
        desglose = await _safeEmpty(
          () => repos.getDesglose(
            id,
            reconciliar: false,
            repararCuenta: false,
          ),
          <DesgloseJugador>[],
        );
      }
    } catch (_) {
      partidos = [];
      desglose = [];
    }

    return OrganizerHomeData(
      resumenes: resumenes,
      convocatorias: convocatorias,
      misInvitaciones: misInvitaciones,
      pagosPorValidar: pagosPorValidar,
      misDeudas: ordenarDeudasPorFecha(misDeudas),
      partidosJugadosRecientes: partidos,
      ultimoPartidoDesglose: desglose,
      cobrosResumen: cobrosResumenDesdeResumenes(resumenes),
    );
  } catch (_) {
    return OrganizerHomeData.empty;
  }
}
