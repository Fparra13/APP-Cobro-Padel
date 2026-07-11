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

    var pushEnviados = 0;
    final sinApp = <Jugador>[];

    for (final entry in conv.titulares) {
      final jugador = entry.jugador;
      final puedePush =
          jugador.keyId.isNotEmpty || jugador.contactEmail != null;

      if (puedePush) {
        await _notificaciones.notificarReprogramacionTitular(
          jugador: jugador,
          partidoId: partidoId,
          fecha: partido.fecha,
          horasLimite: partido.horasLimiteRespuesta,
          recinto: partido.recinto ?? '',
          sportType: partido.sportType,
        );
        pushEnviados++;
      }

      if (!jugador.tienePerfilRemoto && jugador.puedeEnviarWhatsApp) {
        sinApp.add(jugador);
      }
    }

    return ConvocatoriaComunicacionResult(
      pushEnviados: pushEnviados,
      sinApp: sinApp,
    );
  }

  Future<ConvocatoriaComunicacionResult> avisarCancelacion(
    ConvocatoriaCompleta conv,
  ) async {
    final partido = conv.partido;
    final partidoId = partido.id;
    if (partidoId == null) return const ConvocatoriaComunicacionResult();

    var pushEnviados = 0;
    final sinApp = <Jugador>[];

    for (final entry in conv.titulares) {
      if (entry.estado != EstadoConfirmacion.confirmado) continue;

      final jugador = entry.jugador;
      final puedePush =
          jugador.keyId.isNotEmpty || jugador.contactEmail != null;

      if (puedePush) {
        await _notificaciones.notificarCancelacionTitular(
          jugador: jugador,
          partidoId: partidoId,
          fecha: partido.fecha,
          recinto: partido.recinto ?? '',
          sportType: partido.sportType,
        );
        pushEnviados++;
      }

      if (!jugador.tienePerfilRemoto && jugador.puedeEnviarWhatsApp) {
        sinApp.add(jugador);
      }
    }

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

    var pushEnviados = 0;
    final sinApp = <Jugador>[];

    for (final entry in conv.titulares) {
      if (entry.estado != EstadoConfirmacion.invitado) continue;
      final jugador = entry.jugador;
      if (!jugador.tieneMatchPayApp) {
        if (jugador.puedeEnviarWhatsApp) sinApp.add(jugador);
        continue;
      }

      await _notificaciones.notificarRecordatorioManual(
        jugador: jugador,
        partidoId: partidoId,
        fecha: partido.fecha,
        recinto: partido.recinto ?? '',
        sportType: partido.sportType,
      );
      pushEnviados++;
    }

    return ConvocatoriaComunicacionResult(
      pushEnviados: pushEnviados,
      sinApp: sinApp,
    );
  }
}
