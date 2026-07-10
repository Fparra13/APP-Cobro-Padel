import '../models/convocatoria_jugador.dart';
import '../utils/formatters.dart';

class ConvocatoriaMessageService {
  /// Invitación al jugador: idéntica para titular inicial o cupo liberado después.
  String construirInvitacion({
    required ConvocatoriaCompleta convocatoria,
    required String nombreOrganizador,
  }) {
    final p = convocatoria.partido;
    final fecha = formatFechaLegible(p.fecha);
    final hora = formatHora(p.fecha);
    final recinto = p.recinto?.trim();
    final sportLabel = p.sportType.labelEs.toLowerCase();
    final organizador = nombreOrganizador.trim().isEmpty
        ? 'Tu organizador'
        : nombreOrganizador.trim();

    final buffer = StringBuffer()
      ..writeln('$organizador te invitó a un partido de $sportLabel.')
      ..writeln()
      ..writeln('📅 $fecha · $hora');

    if (recinto != null && recinto.isNotEmpty) {
      buffer.writeln('📍 $recinto');
    }

    buffer
      ..writeln()
      ..writeln('¿Puedes asistir?')
      ..writeln('⏱ Tienes ${p.horasLimiteRespuesta} h para responder')
      ..writeln()
      ..writeln('Responde en este chat:')
      ..writeln('✅ Confirmar - [tu nombre]')
      ..writeln('❌ No asistir - [tu nombre]');

    if (p.notas?.trim().isNotEmpty ?? false) {
      buffer
        ..writeln()
        ..writeln('📝 ${p.notas!.trim()}');
    }

    return buffer.toString().trim();
  }

  String construirMensajePersonal({
    required ConvocatoriaCompleta convocatoria,
    required String nombreJugador,
    required String nombreOrganizador,
  }) {
    final saludo = nombreJugador.trim().isEmpty
        ? ''
        : 'Hola ${nombreJugador.trim()}!\n\n';
    return '$saludo${construirInvitacion(
      convocatoria: convocatoria,
      nombreOrganizador: nombreOrganizador,
    )}';
  }
}
