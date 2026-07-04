import '../core/sport_theme.dart';
import '../models/convocatoria_jugador.dart';
import '../utils/formatters.dart';

class ConvocatoriaMessageService {
  String construirMensaje(ConvocatoriaCompleta convocatoria) {
    final p = convocatoria.partido;
    final fecha = formatDiaMensaje(p.fecha);
    final hora = formatHora(p.fecha);
    final recinto = p.recinto?.trim();
    final confirmados = convocatoria.confirmados;
    final cupos = p.cuposMax;

    final sportPalette = SportThemeConfig.paletteFor(p.sportType);
    final buffer = StringBuffer()
      ..writeln('${sportPalette.emoji} *Convocatoria ${p.sportType.labelEs.toLowerCase()}*')
      ..writeln('📅 $fecha · $hora');

    if (recinto != null && recinto.isNotEmpty) {
      buffer.writeln('📍 $recinto');
    }

    buffer
      ..writeln('👥 Cupos: $cupos · Confirmados: $confirmados/$cupos')
      ..writeln('⏱ Tiempo para confirmar: ${p.horasLimiteRespuesta}h')
      ..writeln('📋 Lista de espera: ${convocatoria.enEspera} jugador(es)')
      ..writeln()
      ..writeln('Responde en este chat:')
      ..writeln('✅ Voy - [tu nombre]')
      ..writeln('❌ No voy - [tu nombre]');

    if (p.notas?.trim().isNotEmpty ?? false) {
      buffer
        ..writeln()
        ..writeln('📝 ${p.notas!.trim()}');
    }

    return buffer.toString().trim();
  }
}
