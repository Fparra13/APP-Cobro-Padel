import '../core/app_repositories.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import 'convocatoria_notificacion_service.dart';

class ConvocatoriaSyncResult {
  final int recordatorios;
  final int vencidos;
  final int promovidos;
  final bool autoConfirmado;

  const ConvocatoriaSyncResult({
    this.recordatorios = 0,
    this.vencidos = 0,
    this.promovidos = 0,
    this.autoConfirmado = false,
  });

  bool get huboCambios =>
      recordatorios > 0 || vencidos > 0 || promovidos > 0 || autoConfirmado;
}

/// Lógica automática: recordatorios de plazo, vencimientos, lista de espera y cierre.
class ConvocatoriaListaEsperaService {
  final _notificaciones = ConvocatoriaNotificacionService();
  final _syncInFlight = <int>{};

  /// Ventana para el aviso "te queda menos de 1 h".
  static const recordatorioAntes = Duration(hours: 1);

  AppRepositories get _repos => AppRepositories.active;

  int _cuposOcupados(ConvocatoriaCompleta conv) => conv.titulares
      .where((t) => t.estado.esTitularActivo)
      .length;

  Future<ConvocatoriaSyncResult> sincronizar(int partidoId) async {
    if (_syncInFlight.contains(partidoId)) {
      return const ConvocatoriaSyncResult();
    }
    _syncInFlight.add(partidoId);
    try {
      return await _sincronizarInternal(partidoId);
    } finally {
      _syncInFlight.remove(partidoId);
    }
  }

  Future<ConvocatoriaSyncResult> _sincronizarInternal(int partidoId) async {
    var conv = await _repos.getConvocatoriaCompleta(partidoId);
    if (conv == null || conv.partido.esConfirmado) {
      return const ConvocatoriaSyncResult();
    }

    var recordatorios = 0;
    var vencidos = 0;
    var promovidos = 0;
    final now = DateTime.now();
    final partido = conv.partido;

    // 1) Recordatorio: invitado, plazo futuro y dentro de la última hora.
    for (final entry in conv.titulares) {
      if (entry.estado != EstadoConfirmacion.invitado) continue;
      final limite = entry.tiempoLimite;
      if (limite == null || entry.recordatorioPlazoEnviado) continue;

      final remaining = limite.difference(now);
      if (remaining <= Duration.zero || remaining > recordatorioAntes) {
        continue;
      }

      await _notificaciones.notificarRecordatorioPlazo(
        jugador: entry.jugador,
        partidoId: partidoId,
        fecha: partido.fecha,
        recinto: partido.recinto ?? '',
        sportType: partido.sportType,
      );
      await _repos.marcarRecordatorioPlazoEnviado(
        partidoId: partidoId,
        jugadorId: entry.jugador.keyId,
      );
      recordatorios++;
    }

    // 2) Vencidos: marcar no_respondio + aviso suave (una vez).
    for (final entry in conv.titulares) {
      if (entry.estado == EstadoConfirmacion.noRespondio) continue;
      if (entry.estado != EstadoConfirmacion.invitado) continue;
      if (entry.tiempoLimite == null || !entry.tiempoLimite!.isBefore(now)) {
        continue;
      }

      final avisar = !entry.notificadoVencimiento;
      await _repos.marcarNoRespondio(
        partidoId: partidoId,
        jugadorId: entry.jugador.keyId,
        notificadoVencimiento: true,
      );
      if (avisar) {
        await _notificaciones.notificarPlazoVencido(
          jugador: entry.jugador,
          partidoId: partidoId,
          fecha: partido.fecha,
          recinto: partido.recinto ?? '',
          sportType: partido.sportType,
        );
      }
      vencidos++;
    }

    if (vencidos > 0 || recordatorios > 0) {
      conv = await _repos.getConvocatoriaCompleta(partidoId);
      if (conv == null) {
        return ConvocatoriaSyncResult(
          recordatorios: recordatorios,
          vencidos: vencidos,
        );
      }
    }

    // 3) Promover suplentes a cupos libres.
    while (conv != null &&
        conv.confirmados < conv.partido.cuposMax &&
        conv.suplentes.isNotEmpty &&
        _cuposOcupados(conv) < conv.partido.cuposMax) {
      final promovido = await _repos.promoverSiguienteSuplente(partidoId);
      if (promovido == null) break;

      await _notificaciones.notificarPromocionTitular(
        jugador: promovido,
        partidoId: partidoId,
      );
      promovidos++;
      conv = await _repos.getConvocatoriaCompleta(partidoId);
    }

    var autoConfirmado = false;
    if (conv != null &&
        conv.confirmados >= conv.partido.cuposMax &&
        conv.partido.esOrganizando) {
      await _repos.marcarConvocatoriaConfirmada(partidoId);
      autoConfirmado = true;
    }

    return ConvocatoriaSyncResult(
      recordatorios: recordatorios,
      vencidos: vencidos,
      promovidos: promovidos,
      autoConfirmado: autoConfirmado,
    );
  }

  /// Sincroniza varias convocatorias (p. ej. al abrir inicio).
  Future<void> sincronizarPartidos(Iterable<int> partidoIds) async {
    final ids = partidoIds.toSet();
    for (final id in ids) {
      try {
        await sincronizar(id);
      } catch (_) {}
    }
  }
}
