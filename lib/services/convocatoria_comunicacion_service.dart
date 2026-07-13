import '../domain/partido_lifecycle.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import 'convocatoria_notificacion_service.dart';

class ConvocatoriaComunicacionResult {
  final int pushEnviados;
  final List<Jugador> sinApp;

  const ConvocatoriaComunicacionResult({
    this.pushEnviados = 0,
    this.sinApp = const [],
  });
}

/// Reenvío de avisos tras reprogramar o recordar pendientes.
class ConvocatoriaComunicacionService {
  final _notificaciones = ConvocatoriaNotificacionService();

  Future<ConvocatoriaComunicacionResult> avisarReprogramacion(
    ConvocatoriaCompleta conv,
  ) async {
    final partido = conv.partido;
    final partidoId = partido.id;
    if (partidoId == null) return const ConvocatoriaComunicacionResult();

    final destinatarios = <Jugador>[];
    final sinApp = <Jugador>[];

    for (final entry in conv.titulares) {
      final jugador = entry.jugador;
      final puedePush =
          jugador.keyId.isNotEmpty || jugador.contactEmail != null;
      if (puedePush) destinatarios.add(jugador);
      if (!jugador.tienePerfilRemoto && jugador.puedeEnviarWhatsApp) {
        sinApp.add(jugador);
      }
    }

    final pushEnviados =
        await _notificaciones.notificarReprogramacionTitulares(
      jugadores: destinatarios,
      partidoId: partidoId,
      fecha: partido.fecha,
      horasLimite: partido.horasLimiteRespuesta,
      recinto: partido.recinto ?? '',
      sportType: partido.sportType,
    );

    return ConvocatoriaComunicacionResult(
      pushEnviados: pushEnviados,
      sinApp: sinApp,
    );
  }

  Future<ConvocatoriaComunicacionResult> avisarCancelacion(
    ConvocatoriaCompleta conv, {
    DateTime? reference,
  }) async {
    final partido = conv.partido;
    final partidoId = partido.id;
    if (partidoId == null) return const ConvocatoriaComunicacionResult();

    final destinatarios = <Jugador>[];
    final sinApp = <Jugador>[];
    final ahora = reference ?? PartidoLifecycle.now();

    for (final entry in conv.titulares) {
      if (!PartidoLifecycle.debeRecibirAvisoCancelacion(entry, ahora)) {
        continue;
      }
      final jugador = entry.jugador;
      final puedePush =
          jugador.keyId.isNotEmpty || jugador.contactEmail != null;
      if (puedePush) destinatarios.add(jugador);
      if (!jugador.tienePerfilRemoto && jugador.puedeEnviarWhatsApp) {
        sinApp.add(jugador);
      }
    }

    final pushEnviados = await _notificaciones.notificarCancelacionTitulares(
      jugadores: destinatarios,
      partidoId: partidoId,
      fecha: partido.fecha,
      recinto: partido.recinto ?? '',
      sportType: partido.sportType,
    );

    return ConvocatoriaComunicacionResult(
      pushEnviados: pushEnviados,
      sinApp: sinApp,
    );
  }

  Future<ConvocatoriaComunicacionResult> recordarPendientes(
    ConvocatoriaCompleta conv,
  ) async {
    final partido = conv.partido;
    final partidoId = partido.id;
    if (partidoId == null) return const ConvocatoriaComunicacionResult();

    final conApp = <Jugador>[];
    final sinApp = <Jugador>[];

    for (final entry in conv.titulares) {
      if (entry.estado != EstadoConfirmacion.invitado) continue;
      final jugador = entry.jugador;
      if (!jugador.tieneMatchPayApp) {
        if (jugador.puedeEnviarWhatsApp) sinApp.add(jugador);
        continue;
      }
      conApp.add(jugador);
    }

    final pushEnviados =
        await _notificaciones.notificarRecordatorioManualTitulares(
      jugadores: conApp,
      partidoId: partidoId,
      fecha: partido.fecha,
      recinto: partido.recinto ?? '',
      sportType: partido.sportType,
    );

    return ConvocatoriaComunicacionResult(
      pushEnviados: pushEnviados,
      sinApp: sinApp,
    );
  }
}
