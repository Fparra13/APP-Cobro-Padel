import 'package:flutter/widgets.dart';

import '../core/auth_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/user_facing_error.dart';
import '../core/sport_type.dart';
import '../core/supabase_config.dart';
import '../core/supabase_helpers.dart';
import '../models/convocatoria_jugador.dart';
import '../models/cobros_resumen.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/estadisticas_jugador.dart';
import '../models/estado_partido.dart';
import '../models/gasto_por_concepto.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../models/recinto.dart';
import '../models/saldo_historico.dart';
import '../repositories/backup_repository.dart';
import '../repositories/convocatoria_repository.dart';
import '../repositories/convocatoria_repository_remote.dart';
import '../repositories/estadisticas_repository.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/jugador_repository_remote.dart';
import '../repositories/partido_repository.dart';
import '../repositories/partido_repository_remote.dart';
import '../domain/organizer_cycle_logic.dart';
import '../repositories/ranking_repository.dart';
import '../repositories/recinto_repository_remote.dart';
import '../repositories/repository_types.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/saldo_repository_remote.dart';
import '../repositories/stats_ranking_remote.dart';

int _localId(String key) => int.parse(key);

List<int> _localIds(List<String> keys) =>
    keys.map(_localId).toList(growable: false);

Map<int, double> _localDoubleMap(Map<String, double> map) => {
      for (final e in map.entries) _localId(e.key): e.value,
    };

Map<int, EstadoConfirmacion> _localEstadosMap(
  Map<String, EstadoConfirmacion> map,
) => {
      for (final e in map.entries) _localId(e.key): e.value,
    };

List<CostoVariableInput> _toRemoteCostos(
  List<CostoVariableInput> costos,
) =>
    costos;

/// Repositorio cloud no disponible (sesión sin Supabase, instancia local, etc.).
class AppRepositoriesUnavailable implements Exception {
  const AppRepositoriesUnavailable([this.debugMessage]);

  final String? debugMessage;

  @override
  String toString() =>
      debugMessage ?? 'AppRepositories cloud no disponible';
}

/// Mensaje legible para fallos de datos en acciones de usuario (PDF, backup, etc.).
String dataActionErrorMessage(
  MatchPayStrings l10n,
  Object error,
) {
  if (error is AppRepositoriesUnavailable) {
    return l10n.tr('reposUnavailableSnackbar');
  }
  return userFacingError(error, tr: l10n.tr);
}

/// Punto de acceso unificado a datos locales o Supabase.
class AppRepositories {
  AppRepositories._({required this.useRemote});

  static AppRepositories? _instance;

  /// Incrementa cuando cambian partidos/cobros (p. ej. tras eliminar).
  static final dataRevision = ValueNotifier<int>(0);

  static void notifyDataChanged() {
    dataRevision.value++;
  }

  final bool useRemote;

  bool get isCloud => useRemote;

  final JugadorRepository _jugadorLocal = JugadorRepository();
  final PartidoRepository _partidoLocal = PartidoRepository();
  final ConvocatoriaRepository _convocatoriaLocal = ConvocatoriaRepository();
  final SaldoRepository _saldoLocal = SaldoRepository();
  final RankingRepository _rankingLocal = RankingRepository();
  final EstadisticasRepository _estadisticasLocal = EstadisticasRepository();
  final BackupRepository backup = BackupRepository();

  final JugadorRepositoryRemote _jugadorRemote = JugadorRepositoryRemote();
  final PartidoRepositoryRemote _partidoRemote = PartidoRepositoryRemote();
  final ConvocatoriaRepositoryRemote _convocatoriaRemote =
      ConvocatoriaRepositoryRemote();
  final SaldoRepositoryRemote _saldoRemote = SaldoRepositoryRemote();
  final RankingRepositoryRemote _rankingRemote = RankingRepositoryRemote();
  final EstadisticasRepositoryRemote _estadisticasRemote =
      EstadisticasRepositoryRemote();
  final RecintoRepositoryRemote _recintoRemote = RecintoRepositoryRemote();

  static AppRepositories get I {
    assert(_instance != null, 'AppRepositories no inicializado');
    return _instance!;
  }

  static bool get isReady => _instance != null;

  /// Repositorio activo. Con sesión no crea fallback SQLite silencioso.
  static AppRepositories get active {
    if (_instance != null) {
      _assertCloudWhenLoggedIn(_instance!);
      return _instance!;
    }
    if (AuthService.instance.isLoggedIn) return create();
    throw const AppRepositoriesUnavailable(
      'AppRepositories no inicializado sin sesión.',
    );
  }

  /// Igual que [active] pero devuelve null (p. ej. tareas en background).
  static AppRepositories? get tryActive {
    try {
      return active;
    } on AppRepositoriesUnavailable catch (e) {
      debugPrint('AppRepositories.tryActive: $e');
      return null;
    }
  }

  static void _assertCloudWhenLoggedIn(AppRepositories repos) {
    if (AuthService.instance.isLoggedIn && !repos.useRemote) {
      throw const AppRepositoriesUnavailable(
        'Repositorio local con sesión activa.',
      );
    }
  }

  static AppRepositories create() {
    final loggedIn = AuthService.instance.isLoggedIn;
    if (loggedIn && !SupabaseConfig.isConfigured) {
      throw const AppRepositoriesUnavailable(
        'Supabase no configurado con sesión activa.',
      );
    }
    final remote = loggedIn && SupabaseConfig.isConfigured;
    final repos = AppRepositories._(useRemote: remote);
    _instance = repos;
    return repos;
  }

  static void clear() => _instance = null;

  // --- Jugadores ---

  Future<List<Jugador>> getJugadores({
    bool? soloActivos,
    bool incluirUsuarioActual = false,
  }) {
    if (useRemote) {
      return _jugadorRemote.getAll(
        soloActivos: soloActivos,
        incluirUsuarioActual: incluirUsuarioActual,
      );
    }
    return _jugadorLocal.getAll(soloActivos: soloActivos);
  }

  Future<Jugador?> getJugador(String keyId) {
    if (useRemote) return _jugadorRemote.getById(keyId);
    return _jugadorLocal.getById(_localId(keyId));
  }

  Future<Jugador?> getJugadorPorEmail(String email) {
    if (useRemote) return _jugadorRemote.getByEmail(email);
    return Future.value(null);
  }

  Future<int> insertJugador(Jugador jugador) {
    if (useRemote) return _jugadorRemote.insert(jugador);
    return _jugadorLocal.insert(jugador);
  }

  Future<int> updateJugador(Jugador jugador) {
    if (useRemote) return _jugadorRemote.update(jugador);
    return _jugadorLocal.update(jugador);
  }

  Future<int> deleteJugador(String keyId) {
    if (useRemote) return _jugadorRemote.delete(keyId);
    return _jugadorLocal.delete(_localId(keyId));
  }

  // --- Partidos ---

  Future<List<Partido>> getPartidos({EstadoPartido? soloEstado}) {
    if (useRemote) return _partidoRemote.getAll(soloEstado: soloEstado);
    return _partidoLocal.getAll(soloEstado: soloEstado);
  }

  Future<List<Partido>> getPartidosJugados() {
    if (useRemote) return _partidoRemote.getJugados();
    return _partidoLocal.getJugados();
  }

  Future<List<String>> getRecintosRecientes({int limit = 8}) {
    if (useRemote) return _partidoRemote.getRecintosRecientes(limit: limit);
    return _partidoLocal.getRecintosRecientes(limit: limit);
  }

  Future<PartidoCompleto?> getPartidoCompleto(int partidoId) {
    if (useRemote) return _partidoRemote.getCompleto(partidoId);
    return _partidoLocal.getCompleto(partidoId);
  }

  Future<List<PartidoCompleto>> getPartidosCompletosListaResumen(
    List<int> partidoIds,
  ) {
    if (useRemote) {
      return _partidoRemote.getCompletosListaResumen(partidoIds);
    }
    return _partidoLocal.getCompletosListaResumen(partidoIds);
  }

  /// Lectura de desglose. [reconciliar] ya no está soportado.
  /// [repararCuenta] es costoso; por defecto off (solo reparación explícita).
  /// Si ya tienes [completo], pásalo para evitar un fetch duplicado.
  Future<List<DesgloseJugador>> getDesglose(
    int partidoId, {
    bool reconciliar = false,
    bool repararCuenta = false,
    PartidoCompleto? completo,
  }) {
    if (useRemote) {
      return _partidoRemote.getDesglose(
        partidoId,
        reconciliar: reconciliar,
        repararCuenta: repararCuenta,
        completo: completo,
      );
    }
    return _partidoLocal.getDesglose(partidoId);
  }

  Future<List<ResumenJugador>> getResumenJugadores({bool reconciliar = false}) {
    if (useRemote) {
      return _partidoRemote.getResumenJugadores(reconciliar: reconciliar);
    }
    return _partidoLocal.getResumenJugadores();
  }

  Future<CobrosResumen> getCobrosResumen() async {
    if (useRemote) {
      return _partidoRemote.getCobrosResumen();
    }
    final resumenes = await _partidoLocal.getResumenJugadores();
    return cobrosResumenDesdeResumenes(resumenes);
  }

  /// Reparación manual fuera del flujo normal. No invocar al abrir fichas.
  @Deprecated('Solo reparación manual; no usar en flujo normal')
  Future<void> reconciliarJugador(String jugadorKey) async {
    if (useRemote) {
      await _partidoRemote.reconciliarDetallesJugador(jugadorKey);
      return;
    }
    await _partidoLocal.reconciliarDetallesJugador(_localId(jugadorKey));
  }

  Future<PartidoCompleto?> getUltimoPartido() {
    if (useRemote) return _partidoRemote.getUltimoPartido();
    return _partidoLocal.getUltimoPartido();
  }

  Future<List<PartidoCompleto>> getPartidosJugadosRecientesResumen({
    int limit = 8,
  }) {
    if (useRemote) {
      return _partidoRemote.getPartidosJugadosRecientesResumen(limit: limit);
    }
    return _partidoLocal.getPartidosJugadosRecientesResumen(limit: limit);
  }

  Future<int> guardarPartido({
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
  }) {
    if (useRemote) {
      return _partidoRemote.guardarPartido(
        partido: partido,
        jugadoresAsistentes: jugadoresAsistentes,
        montoPagadoPorJugador: montoPagadoPorJugador,
        costosVariables: _toRemoteCostos(costosVariables),
        saldosAnterioresSnapshot: saldosAnterioresSnapshot,
      );
    }
    return _partidoLocal.guardarPartido(
      partido: partido,
      jugadoresAsistentes: _localIds(jugadoresAsistentes),
      montoPagadoPorJugador: _localDoubleMap(montoPagadoPorJugador),
      costosVariables: costosVariables
          .map(
            (cv) => (
              concepto: cv.concepto,
              montoTotal: cv.montoTotal,
              jugadores: _localIds(cv.jugadores),
              comprobantePath: cv.comprobantePath,
              iconKey: cv.iconKey,
            ),
          )
          .toList(),
      saldosAnterioresSnapshot: saldosAnterioresSnapshot != null
          ? _localDoubleMap(saldosAnterioresSnapshot)
          : null,
    );
  }

  Future<void> actualizarPartido({
    required int partidoId,
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
  }) {
    if (useRemote) {
      return _partidoRemote.actualizarPartido(
        partidoId: partidoId,
        partido: partido,
        jugadoresAsistentes: jugadoresAsistentes,
        montoPagadoPorJugador: montoPagadoPorJugador,
        costosVariables: _toRemoteCostos(costosVariables),
        saldosAnterioresSnapshot: saldosAnterioresSnapshot,
      );
    }
    return _partidoLocal.actualizarPartido(
      partidoId: partidoId,
      partido: partido,
      jugadoresAsistentes: _localIds(jugadoresAsistentes),
      montoPagadoPorJugador: _localDoubleMap(montoPagadoPorJugador),
      costosVariables: costosVariables
          .map(
            (cv) => (
              concepto: cv.concepto,
              montoTotal: cv.montoTotal,
              jugadores: _localIds(cv.jugadores),
              comprobantePath: cv.comprobantePath,
              iconKey: cv.iconKey,
            ),
          )
          .toList(),
    );
  }

  Future<void> completarPartidoOrganizado({
    required int partidoId,
    required Partido partido,
    required List<String> jugadoresAsistentes,
    required Map<String, double> montoPagadoPorJugador,
    required List<CostoVariableInput> costosVariables,
    Map<String, double>? saldosAnterioresSnapshot,
  }) {
    if (useRemote) {
      return _partidoRemote.completarPartidoOrganizado(
        partidoId: partidoId,
        partido: partido,
        jugadoresAsistentes: jugadoresAsistentes,
        montoPagadoPorJugador: montoPagadoPorJugador,
        costosVariables: _toRemoteCostos(costosVariables),
        saldosAnterioresSnapshot: saldosAnterioresSnapshot,
      );
    }
    return _partidoLocal.completarPartidoOrganizado(
      partidoId: partidoId,
      partido: partido,
      jugadoresAsistentes: _localIds(jugadoresAsistentes),
      montoPagadoPorJugador: _localDoubleMap(montoPagadoPorJugador),
      costosVariables: costosVariables
          .map(
            (cv) => (
              concepto: cv.concepto,
              montoTotal: cv.montoTotal,
              jugadores: _localIds(cv.jugadores),
              comprobantePath: cv.comprobantePath,
              iconKey: cv.iconKey,
            ),
          )
          .toList(),
      saldosAnterioresSnapshot: saldosAnterioresSnapshot != null
          ? _localDoubleMap(saldosAnterioresSnapshot)
          : null,
    );
  }

  Future<void> eliminarPartido(int id) async {
    if (useRemote) {
      await _partidoRemote.eliminarPartido(id);
    } else {
      await _partidoLocal.eliminarPartido(id);
    }
    notifyDataChanged();
  }

  Future<void> registrarAbono({
    required String jugadorId,
    required double monto,
    String concepto = 'Abono manual',
  }) async {
    if (useRemote) {
      await _partidoRemote.registrarAbono(
        jugadorId: jugadorId,
        monto: monto,
        concepto: concepto,
      );
    } else {
      await _partidoLocal.registrarAbono(
        jugadorId: _localId(jugadorId),
        monto: monto,
        concepto: concepto,
      );
    }
    notifyDataChanged();
  }

  Future<List<DeudaPartidoAnterior>> getDeudasPartidosAnteriores({
    required String jugadorId,
    required int partidoActualId,
  }) {
    if (useRemote) {
      return _partidoRemote.getDeudasPartidosAnteriores(
        jugadorId: jugadorId,
        partidoActualId: partidoActualId,
      );
    }
    return _partidoLocal.getDeudasPartidosAnteriores(
      jugadorId: _localId(jugadorId),
      partidoActualId: partidoActualId,
    );
  }

  Future<List<DeudaPartidoAnterior>> getPartidosPendientesJugador(
    String jugadorId, {
    bool reconciliar = false,
  }) {
    if (useRemote) {
      return _partidoRemote.getPartidosPendientesJugador(
        jugadorId,
        reconciliar: reconciliar,
      );
    }
    return _partidoLocal.getPartidosPendientesJugador(
      _localId(jugadorId),
      reconciliar: reconciliar,
    );
  }

  Future<({int partidosJugados, int partidosPagados, int partidosImpagos})>
      getResumenPartidosJugador(String jugadorId) {
    if (useRemote) {
      return _partidoRemote.getResumenPartidosJugador(jugadorId);
    }
    return _partidoLocal.getResumenPartidosJugador(_localId(jugadorId));
  }

  Future<List<ResumenJugador>> getDeudoresVencidos(int diasMinimos) {
    if (useRemote) return _partidoRemote.getDeudoresVencidos(diasMinimos);
    return _partidoLocal.getDeudoresVencidos(diasMinimos);
  }

  // --- Convocatorias ---

  Future<List<ConvocatoriaCompleta>> getConvocatoriasActivas() {
    if (useRemote) return _convocatoriaRemote.getActivas();
    return _convocatoriaLocal.getActivas();
  }

  Future<ConvocatoriaCompleta?> getConvocatoriaCompleta(int partidoId) {
    if (useRemote) return _convocatoriaRemote.getCompleta(partidoId);
    return _convocatoriaLocal.getCompleta(partidoId);
  }

  Future<ConvocatoriaCompleta?> getConvocatoriaRosterParaJugador({
    required int partidoId,
    required Partido partido,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.getRosterParaJugador(
        partidoId: partidoId,
        partido: partido,
      );
    }
    return _convocatoriaLocal.getCompleta(partidoId);
  }

  Future<int> crearConvocatoria({
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
    SportType? sportType,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.crear(
        fecha: fecha,
        recinto: recinto,
        recintoId: recintoId,
        recintoMapsUrl: recintoMapsUrl,
        recintoLat: recintoLat,
        recintoLng: recintoLng,
        notas: notas,
        cuposMax: cuposMax,
        horasLimiteRespuesta: horasLimiteRespuesta,
        jugadores: jugadores,
        sportType: sportType,
      );
    }
    return _convocatoriaLocal.crear(
      fecha: fecha,
      recinto: recinto,
      notas: notas,
      cuposMax: cuposMax,
      horasLimiteRespuesta: horasLimiteRespuesta,
      jugadores: jugadores,
      sportType: sportType,
    );
  }

  Future<void> actualizarConvocatoria({
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
  }) {
    if (useRemote) {
      return _convocatoriaRemote.actualizar(
        partidoId: partidoId,
        fecha: fecha,
        recinto: recinto,
        recintoId: recintoId,
        recintoMapsUrl: recintoMapsUrl,
        recintoLat: recintoLat,
        recintoLng: recintoLng,
        notas: notas,
        cuposMax: cuposMax,
        horasLimiteRespuesta: horasLimiteRespuesta,
        jugadores: jugadores,
        sportType: sportType,
      );
    }
    return _convocatoriaLocal.actualizar(
      partidoId: partidoId,
      fecha: fecha,
      recinto: recinto,
      notas: notas,
      cuposMax: cuposMax,
      horasLimiteRespuesta: horasLimiteRespuesta,
      jugadores: jugadores,
      sportType: sportType,
    );
  }

  Future<List<Recinto>> getMisRecintos() {
    if (useRemote) return _recintoRemote.getMisRecintos();
    return Future.value([]);
  }

  Future<Recinto> crearRecinto({
    required String nombre,
    required String mapsInput,
    String? direccion,
  }) {
    if (!useRemote) {
      throw Exception('Recintos con mapa requieren conexión a Supabase');
    }
    return _recintoRemote.crear(
      nombre: nombre,
      mapsInput: mapsInput,
      direccion: direccion,
    );
  }

  Future<void> eliminarRecinto(int id) {
    if (!useRemote) return Future.value();
    return _recintoRemote.eliminar(id);
  }

  Future<void> actualizarConfirmacion({
    required int partidoId,
    required String jugadorId,
    required EstadoConfirmacion estado,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.actualizarConfirmacion(
        partidoId: partidoId,
        jugadorId: jugadorId,
        estado: estado,
      );
    }
    return _convocatoriaLocal.actualizarConfirmacion(
      partidoId: partidoId,
      jugadorId: _localId(jugadorId),
      estado: estado,
    );
  }

  Future<void> aplicarConfirmaciones({
    required int partidoId,
    required Map<String, EstadoConfirmacion> cambios,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.aplicarConfirmaciones(
        partidoId: partidoId,
        cambios: cambios,
      );
    }
    return _convocatoriaLocal.aplicarConfirmaciones(
      partidoId: partidoId,
      cambios: _localEstadosMap(cambios),
    );
  }

  Future<List<String>> getConfirmadosIds(int partidoId) async {
    if (useRemote) {
      return _convocatoriaRemote.getConfirmadosIds(partidoId);
    }
    final ids = await _convocatoriaLocal.getConfirmadosIds(partidoId);
    return ids.map((id) => id.toString()).toList();
  }

  Future<void> activarTiemposLimiteConvocatoria({
    required int partidoId,
    required int horasLimite,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.activarTiemposLimiteConvocatoria(
        partidoId: partidoId,
        horasLimite: horasLimite,
      );
    }
    return _convocatoriaLocal.activarTiemposLimiteConvocatoria(
      partidoId: partidoId,
      horasLimite: horasLimite,
    );
  }

  Future<void> marcarConvocatoriaConfirmada(int partidoId) {
    if (useRemote) return _convocatoriaRemote.marcarConfirmado(partidoId);
    return _convocatoriaLocal.marcarConfirmado(partidoId);
  }

  Future<void> reabrirConvocatoriaOrganizador(int partidoId) {
    if (useRemote) {
      return _convocatoriaRemote.reabrirConvocatoriaOrganizador(partidoId);
    }
    return _convocatoriaLocal.reabrirConvocatoriaOrganizador(partidoId);
  }

  Future<void> actualizarOrdenListaEspera({
    required int partidoId,
    required List<String> jugadorIdsEnOrden,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.actualizarOrdenListaEspera(
        partidoId: partidoId,
        jugadorIdsEnOrden: jugadorIdsEnOrden,
      );
    }
    return _convocatoriaLocal.actualizarOrdenListaEspera(
      partidoId: partidoId,
      jugadorIdsEnOrden: jugadorIdsEnOrden,
    );
  }

  Future<void> marcarNoRespondio({
    required int partidoId,
    required String jugadorId,
    bool notificadoVencimiento = false,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.marcarNoRespondio(
        partidoId: partidoId,
        jugadorId: jugadorId,
        notificadoVencimiento: notificadoVencimiento,
      );
    }
    return _convocatoriaLocal.marcarNoRespondio(
      partidoId: partidoId,
      jugadorId: _localId(jugadorId),
      notificadoVencimiento: notificadoVencimiento,
    );
  }

  Future<void> marcarRecordatorioPlazoEnviado({
    required int partidoId,
    required String jugadorId,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.marcarRecordatorioPlazoEnviado(
        partidoId: partidoId,
        jugadorId: jugadorId,
      );
    }
    return _convocatoriaLocal.marcarRecordatorioPlazoEnviado(
      partidoId: partidoId,
      jugadorId: _localId(jugadorId),
    );
  }

  Future<Jugador?> promoverSiguienteSuplente(int partidoId) {
    if (useRemote) {
      return _convocatoriaRemote.promoverSiguienteSuplente(partidoId);
    }
    return _convocatoriaLocal.promoverSiguienteSuplente(partidoId);
  }

  Future<void> eliminarConvocatoria(int partidoId) {
    if (useRemote) return _convocatoriaRemote.eliminar(partidoId);
    return _convocatoriaLocal.eliminar(partidoId);
  }

  Future<void> cancelarConvocatoria(int partidoId) {
    if (useRemote) return _convocatoriaRemote.cancelar(partidoId);
    return _convocatoriaLocal.cancelar(partidoId);
  }

  Future<void> reprogramarConvocatoria({
    required int partidoId,
    required DateTime nuevaFecha,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.reprogramar(
        partidoId: partidoId,
        nuevaFecha: nuevaFecha,
      );
    }
    return _convocatoriaLocal.reprogramar(
      partidoId: partidoId,
      nuevaFecha: nuevaFecha,
    );
  }

  Future<List<ConvocatoriaJugadorEntry>> getMisConvocatoriasPendientes() async {
    if (useRemote) {
      return _convocatoriaRemote.getMisConvocatoriasPendientes();
    }
    return [];
  }

  Future<void> relinkConvocatoriasPorEmail() async {
    if (!useRemote) return;
    try {
      await SupabaseHelpers.client.rpc('relink_convocatorias_por_email');
    } catch (_) {
      // RPC no desplegado aún: ignorar silenciosamente.
    }
  }

  Future<List<MiConvocatoria>> getMisConvocatoriasComoJugador() async {
    await relinkConvocatoriasPorEmail();
    if (useRemote) {
      return _convocatoriaRemote.getMisConvocatoriasComoJugador();
    }
    return [];
  }

  Future<List<MiConvocatoria>> getCancelacionesJugador() async {
    await relinkConvocatoriasPorEmail();
    if (useRemote) {
      return _convocatoriaRemote.getCancelacionesJugador();
    }
    return [];
  }

  Future<MiConvocatoria?> getCancelacionJugador(int partidoId) async {
    await relinkConvocatoriasPorEmail();
    if (useRemote) {
      return _convocatoriaRemote.getCancelacionJugador(partidoId);
    }
    return null;
  }

  Future<MiConvocatoria?> getMiConvocatoria(int partidoId) async {
    await relinkConvocatoriasPorEmail();
    if (useRemote) {
      return _convocatoriaRemote.getMiConvocatoria(partidoId);
    }
    return null;
  }

  Future<void> responderConvocatoria({
    required int partidoId,
    required bool confirmo,
  }) {
    if (useRemote) {
      return _convocatoriaRemote.responderConvocatoria(
        partidoId: partidoId,
        confirmo: confirmo,
      );
    }
    throw UnsupportedError('Requiere conexión a Supabase');
  }

  Future<List<DetallePartido>> getMisDeudasPendientes({
    bool reconciliar = false,
  }) async {
    if (useRemote) {
      return _partidoRemote.getMisDeudasPendientes(reconciliar: reconciliar);
    }
    return Future.value([]);
  }

  Future<List<DetallePartido>> getMisPartidosJugados({int limit = 30}) async {
    if (useRemote) return _partidoRemote.getMisPartidosJugados(limit: limit);
    return Future.value([]);
  }

  Future<List<DetallePartido>> getPagosPorValidar() async {
    if (useRemote) return _partidoRemote.getPagosPorValidar();
    return Future.value([]);
  }

  Future<DesgloseJugador?> getMiDesglosePartido(int partidoId) {
    if (useRemote) return _partidoRemote.getMiDesglosePartido(partidoId);
    return Future.value(null);
  }

  Future<Map<int, double>> getMisSaldosAnterioresPartidos(
    Iterable<int> partidoIds,
  ) {
    if (useRemote) {
      return _partidoRemote.getMisSaldosAnterioresPartidos(partidoIds);
    }
    return Future.value({});
  }

  Future<List<GastoPorConcepto>> getMisGastosPorConcepto({
    DateTime? desde,
    DateTime? hasta,
  }) {
    if (useRemote) {
      return _partidoRemote.getMisGastosPorConcepto(
        desde: desde,
        hasta: hasta,
      );
    }
    return Future.value([]);
  }

  Future<void> subirComprobantePago({
    required int detalleId,
    required String storagePath,
    required double montoDeclarado,
    required bool esAbono,
  }) {
    if (useRemote) {
      return _partidoRemote.subirComprobantePago(
        detalleId: detalleId,
        storagePath: storagePath,
        montoDeclarado: montoDeclarado,
        esAbono: esAbono,
      );
    }
    throw UnsupportedError('Requiere conexión a Supabase');
  }

  Future<void> validarComprobantePago({
    required int detalleId,
    required bool aprobado,
  }) async {
    if (useRemote) {
      await _partidoRemote.validarComprobantePago(
        detalleId: detalleId,
        aprobado: aprobado,
      );
    } else {
      throw UnsupportedError('Requiere conexión a Supabase');
    }
    notifyDataChanged();
  }

  // --- Saldos ---

  Future<List<SaldoHistorico>> getSaldosByPartido(int partidoId) {
    if (useRemote) return _saldoRemote.getByPartido(partidoId);
    return _saldoLocal.getByPartido(partidoId);
  }

  Future<List<SaldoHistorico>> getSaldosByJugador(String jugadorId) {
    if (useRemote) return _saldoRemote.getByJugador(jugadorId);
    return _saldoLocal.getByJugador(_localId(jugadorId));
  }

  // --- Ranking / estadísticas ---

  Future<List<RankingJugador>> getRanking() {
    if (useRemote) return _rankingRemote.getRanking();
    return _rankingLocal.getRanking();
  }

  List<RankingJugador> mejoresPagadores(List<RankingJugador> all) {
    if (useRemote) return _rankingRemote.mejoresPagadores(all);
    return _rankingLocal.mejoresPagadores(all);
  }

  List<RankingJugador> peoresPagadores(List<RankingJugador> all) {
    if (useRemote) return _rankingRemote.peoresPagadores(all);
    return _rankingLocal.peoresPagadores(all);
  }

  Future<List<EstadisticasJugador>> getEstadisticas() {
    if (useRemote) return _estadisticasRemote.getAll();
    return _estadisticasLocal.getAll();
  }

  List<EstadisticasJugador> masParticipacion(List<EstadisticasJugador> all) {
    if (useRemote) return _estadisticasRemote.masParticipacion(all);
    return _estadisticasLocal.masParticipacion(all);
  }

  List<EstadisticasJugador> mejoresPagadoresStats(
    List<EstadisticasJugador> all,
  ) {
    if (useRemote) return _estadisticasRemote.mejoresPagadores(all);
    return _estadisticasLocal.mejoresPagadores(all);
  }

  List<EstadisticasJugador> pagadoresRapidos(List<EstadisticasJugador> all) {
    if (useRemote) return _estadisticasRemote.pagadoresRapidos(all);
    return _estadisticasLocal.pagadoresRapidos(all);
  }

  List<EstadisticasJugador> masActivosRecientes(
    List<EstadisticasJugador> all,
  ) {
    if (useRemote) return _estadisticasRemote.masActivosRecientes(all);
    return _estadisticasLocal.masActivosRecientes(all);
  }

  List<EstadisticasJugador> reyConvocatoria(List<EstadisticasJugador> all) {
    if (useRemote) return _estadisticasRemote.reyConvocatoria(all);
    return _estadisticasLocal.reyConvocatoria(all);
  }

  List<EstadisticasJugador> masAportado(List<EstadisticasJugador> all) {
    if (useRemote) return _estadisticasRemote.masAportado(all);
    return _estadisticasLocal.masAportado(all);
  }

  List<EstadisticasJugador> mayorDeuda(List<EstadisticasJugador> all) {
    if (useRemote) return _estadisticasRemote.mayorDeuda(all);
    return _estadisticasLocal.mayorDeuda(all);
  }
}

class AppRepositoriesScope extends InheritedWidget {
  final AppRepositories repos;

  const AppRepositoriesScope({
    super.key,
    required this.repos,
    required super.child,
  });

  /// Seguro fuera de [build] (p. ej. initState / callbacks async).
  /// No usa [dependOnInheritedWidgetOfExactType] para no fallar al montar la ruta.
  static AppRepositories of(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<AppRepositoriesScope>();
    if (scope != null) return scope.repos;
    if (AppRepositories.isReady) return AppRepositories.I;
    throw StateError(
      'AppRepositories no inicializado. Cierra sesión e inicia de nuevo.',
    );
  }

  @override
  bool updateShouldNotify(AppRepositoriesScope oldWidget) =>
      oldWidget.repos.useRemote != repos.useRemote;
}

extension AppRepositoriesContext on BuildContext {
  AppRepositories get repos => AppRepositoriesScope.of(this);
}
