import '../core/app_repositories.dart';
import '../domain/partido_lifecycle.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import 'convocatoria_notificacion_service.dart';

class ConvocatoriaSyncResult {
  final int recordatorios;
  final int vencidos;
  final int promovidos;
  final bool autoConfirmado;
  final bool reabierta;

  const ConvocatoriaSyncResult({
    this.recordatorios = 0,
    this.vencidos = 0,
    this.promovidos = 0,
    this.autoConfirmado = false,
    this.reabierta = false,
  });

  bool get huboCambios =>
      recordatorios > 0 ||
      vencidos > 0 ||
      promovidos > 0 ||
      autoConfirmado ||
      reabierta;
}

/// Lógica automática: recordatorios de plazo, vencimientos, lista de espera y cierre.
class ConvocatoriaListaEsperaService {
  final _notificaciones = ConvocatoriaNotificacionService();
  final _syncInFlight = <int>{};

  /// Ventana para el aviso "te queda menos de 1 h".
  static const recordatorioAntes = Duration(hours: 1);

  int _cuposOcupados(ConvocatoriaCompleta conv) => conv.titulares
      .where((t) => t.estado.esTitularActivo)
      .length;

  Future<ConvocatoriaSyncResult> sincronizar(int partidoId) async {
    if (_syncInFlight.contains(partidoId)) {
      return const ConvocatoriaSyncResult();
    }
    if (AppRepositories.tryActive == null) {
      return const ConvocatoriaSyncResult();
    }
    _syncInFlight.add(partidoId);
    try {
      return await _sincronizarInternal(partidoId);
    } on AppRepositoriesUnavailable {
      return const ConvocatoriaSyncResult();
    } finally {
      _syncInFlight.remove(partidoId);
    }
  }

  Future<ConvocatoriaSyncResult> _sincronizarInternal(int partidoId) async {
    final repos = AppRepositories.tryActive;
    if (repos == null) return const ConvocatoriaSyncResult();
    var conv = await repos.getConvocatoriaCompleta(partidoId);
    if (conv == null) {
      return const ConvocatoriaSyncResult();
    }

    var recordatorios = 0;
    var vencidos = 0;
    var promovidos = 0;
    final now = DateTime.now();
    final partido = conv.partido;

    // 0) Convocatoria expirada (hora del partido): cerrar respuestas pendientes.
    if (PartidoLifecycle.convocatoriaExpirada(partido, now)) {
      for (final entry in conv.titulares) {
        if (entry.estado != EstadoConfirmacion.invitado) continue;
        final avisar = !entry.notificadoVencimiento;
        await repos.marcarNoRespondio(
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
      return ConvocatoriaSyncResult(vencidos: vencidos);
    }

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
      await repos.marcarRecordatorioPlazoEnviado(
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
      await repos.marcarNoRespondio(
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
      conv = await repos.getConvocatoriaCompleta(partidoId);
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
      final promovido = await repos.promoverSiguienteSuplente(partidoId);
      if (promovido == null) break;

      await _notificaciones.notificarPromocionTitular(
        jugador: promovido,
        partidoId: partidoId,
      );
      promovidos++;
      conv = await repos.getConvocatoriaCompleta(partidoId);
    }

    var autoConfirmado = false;
    var reabierta = false;
    if (conv != null) {
      if (conv.partido.esConfirmado &&
          conv.confirmados < conv.partido.cuposMax) {
        await repos.reabrirConvocatoriaOrganizador(partidoId);
        reabierta = true;
        conv = await repos.getConvocatoriaCompleta(partidoId);
      }
      if (conv != null &&
          conv.confirmados >= conv.partido.cuposMax &&
          conv.partido.esOrganizando) {
        await repos.marcarConvocatoriaConfirmada(partidoId);
        autoConfirmado = true;
      }
    }

    return ConvocatoriaSyncResult(
      recordatorios: recordatorios,
      vencidos: vencidos,
      promovidos: promovidos,
      autoConfirmado: autoConfirmado,
      reabierta: reabierta,
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
