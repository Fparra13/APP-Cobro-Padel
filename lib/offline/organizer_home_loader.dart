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
  return loadWithOfflineSnapshot(
    snapshotKey: organizerHomeSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () =>
        fetchOverride != null ? fetchOverride() : _fetchFromRepos(repos!),
    encode: (data) => data.toJson(),
    decode: OrganizerHomeData.fromJson,
  );
}

Future<OfflineScreenLoadResult<OrganizerCobrosData>> loadOrganizerCobros({
  required AppRepositories repos,
  required OfflineSnapshotStore? snapshotStore,
}) {
  return loadWithOfflineSnapshot(
    snapshotKey: organizerCobrosSnapshotKey,
    snapshotStore: snapshotStore,
    fetch: () async {
      final resumenes =
          await repos.getResumenJugadores(reconciliar: false);
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

Future<OrganizerHomeData> _fetchFromRepos(AppRepositories repos) async {
  final results = await Future.wait([
    repos.getResumenJugadores(reconciliar: false),
    repos.getConvocatoriasActivas(),
    MisInvitacionesPanel.cargarPendientes(repos),
    repos.isCloud
        ? repos.getPagosPorValidar()
        : Future<List<DetallePartido>>.value([]),
    repos.isCloud
        ? repos.getMisDeudasPendientes()
        : Future<List<DetallePartido>>.value([]),
    repos.getPartidosJugadosRecientesResumen(limit: 8).then(
      (partidos) async {
        if (partidos.isEmpty || partidos.first.partido.id == null) {
          return (partidos: partidos, desglose: <DesgloseJugador>[]);
        }
        final desglose = await repos.getDesglose(
          partidos.first.partido.id!,
          reconciliar: false,
        );
        return (partidos: partidos, desglose: desglose);
      },
    ),
  ]);
  final resumenes = results[0] as List<ResumenJugador>;
  final cobrosResumen = cobrosResumenDesdeResumenes(resumenes);
  final ultimoPack = results[5] as ({
    List<PartidoCompleto> partidos,
    List<DesgloseJugador> desglose,
  });
  return OrganizerHomeData(
    resumenes: resumenes,
    convocatorias: results[1] as List<ConvocatoriaCompleta>,
    misInvitaciones: results[2] as List<MiConvocatoria>,
    pagosPorValidar: results[3] as List<DetallePartido>,
    misDeudas: ordenarDeudasPorFecha(results[4] as List<DetallePartido>),
    partidosJugadosRecientes: ultimoPack.partidos,
    ultimoPartidoDesglose: ultimoPack.desglose,
    cobrosResumen: cobrosResumen,
  );
}
