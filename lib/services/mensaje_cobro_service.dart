import '../core/sport_theme.dart';
import '../core/sport_type.dart';
import '../models/datos_pago_organizador.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/desglose_jugador.dart';
import '../models/partido.dart';
import '../utils/formatters.dart';

/// Textos de notificaciones push / recordatorios de cobro por jugador.
class MensajeCobroService {
  static String construirDetallePartido({
    required Partido partido,
    required DesgloseJugador desglose,
    required List<DeudaPartidoAnterior> deudasAnteriores,
    required DatosPagoOrganizador pago,
  }) {
    final sportPalette = SportThemeConfig.paletteFor(partido.sportType);
    final lineas = <String>[
      '${sportPalette.emoji} *${partido.sportType.labelEs} — ${formatFecha(partido.fecha)}*',
    ];

    if (partido.recinto != null && partido.recinto!.trim().isNotEmpty) {
      lineas.add('📍 ${partido.recinto!.trim()}');
    }

    lineas
      ..add('')
      ..add('Hola ${formatNombreSaludo(desglose.nombre)}!')
      ..add('')
      ..add('*Detalle de este encuentro:*');

    for (final l in desglose.lineas) {
      lineas.add('• ${l.concepto}: ${formatMoney(l.monto)}');
    }

    if (desglose.saldoFavorAplicado > 0) {
      lineas.add(
        '• Saldo a favor aplicado: −${formatMoney(desglose.saldoFavorAplicado)}',
      );
    }

    lineas.add('Subtotal encuentro: ${formatMoney(desglose.totalPartido)}');

    if (desglose.saldoAnterior > 0.005) {
      lineas.add(
        '• Pendiente anterior: ${formatMoney(desglose.saldoAnterior)}',
      );
    }

    if (desglose.saldoFavorAplicado > 0 && desglose.netoAPagarPartido <= 0) {
      lineas.add('✅ Encuentro cubierto con saldo a favor');
    } else if (desglose.alDiaOrganizador) {
      if (desglose.creditoCuenta > 0.005) {
        lineas.add(
          '✅ Al día — Saldo a favor: ${formatMoney(desglose.creditoCuenta)}',
        );
      } else if (desglose.generaSaldoAFavorPartido) {
        lineas.add(
          '✅ Al día — Saldo a favor: ${formatMoney(-desglose.saldoRestantePartido)}',
        );
      } else if (desglose.montoPagado > 0) {
        lineas.add('Aportaste: ${formatMoney(desglose.montoPagado)}');
      } else {
        lineas.add('✅ Encuentro al día');
      }
    } else {
      if (desglose.montoPagado > 0) {
        lineas.add('Aportaste: ${formatMoney(desglose.montoPagado)}');
      }
      lineas.add(
        'Total pendiente: *${formatMoney(desglose.pendienteOrganizador)}*',
      );
    }

    lineas.addAll(pago.toMessageLines(title: 'Datos para aportar'));

    lineas.add('');
    lineas.addAll(
      desglose.alDiaOrganizador
          ? _lineasCierreAlDia(partido.sportType)
          : _lineasCierrePendiente(partido.sportType),
    );

    return lineas.join('\n');
  }

  /// Mensaje simple cuando no hay desglose disponible.
  static String construirRecordatorio({
    required String nombreJugador,
    required double saldo,
    required List<DeudaPartidoAnterior> partidos,
    required DatosPagoOrganizador pago,
  }) {
    final lineas = <String>[
      '🏆 *Recordatorio Kloovi*',
      '',
      'Hola ${formatNombreSaludo(nombreJugador)}!',
      '',
      'Tienes un saldo pendiente de *${formatMoney(saldo)}*.',
    ];

    if (partidos.isNotEmpty) {
      lineas
        ..add('')
        ..add('*Encuentros pendientes:*');
      for (final p in partidos) {
        final f = formatFecha(p.fecha);
        final r = p.recinto?.trim();
        final sportEmoji = SportThemeConfig.paletteFor(p.sportType).emoji;
        final sportLabel = p.sportType.labelEs;
        final lugar = r != null && r.isNotEmpty ? '$f - $r' : f;
        lineas.add(
          '• $sportEmoji $sportLabel · $lugar: ${formatMoney(p.pendienteNeto)}',
        );
      }
    }

    lineas.addAll(pago.toMessageLines(title: 'Datos para aportar'));

    lineas
      ..add('')
      ..addAll(_lineasCierrePendiente(
        partidos.isNotEmpty ? partidos.first.sportType : SportType.padel,
      ));

    return lineas.join('\n');
  }

  static List<String> _lineasCierrePendiente(SportType sport) {
    final emoji = SportThemeConfig.paletteFor(sport).emoji;
    return [
      'Cuando puedas aporta fuera de Kloovi y quedamos al día 🙌',
      '¡Nos vemos pronto! $emoji🔥',
    ];
  }

  static List<String> _lineasCierreAlDia(SportType sport) {
    final emoji = SportThemeConfig.paletteFor(sport).emoji;
    return [
      '¡Gracias por estar al día! 🙌',
      '¡Nos vemos pronto! $emoji🔥',
    ];
  }
}
