import '../models/deuda_partido_anterior.dart';
import '../models/desglose_jugador.dart';
import '../models/partido.dart';
import '../utils/formatters.dart';

/// Mensajes de WhatsApp con detalle de cobros por jugador.
/// Usa *negrita* (formato nativo de WhatsApp) y líneas en blanco entre bloques.
class MensajeCobroService {
  static String construirDetallePartido({
    required Partido partido,
    required DesgloseJugador desglose,
    required List<DeudaPartidoAnterior> deudasAnteriores,
    required String titular,
    required String banco,
    required String cuenta,
  }) {
    final lineas = <String>[
      '🎾 *Pádel — ${formatFecha(partido.fecha)}*',
    ];

    if (partido.recinto != null && partido.recinto!.trim().isNotEmpty) {
      lineas.add('📍 ${partido.recinto!.trim()}');
    }

    lineas
      ..add('')
      ..add('Hola ${formatNombreSaludo(desglose.nombre)}!')
      ..add('')
      ..add('*Detalle de este partido:*');

    for (final l in desglose.lineas) {
      lineas.add('• ${l.concepto}: ${formatMoney(l.monto)}');
    }

    if (desglose.saldoFavorAplicado > 0) {
      lineas.add(
        '• Saldo a favor aplicado: −${formatMoney(desglose.saldoFavorAplicado)}',
      );
    }

    lineas.add('Subtotal partido: ${formatMoney(desglose.totalPartido)}');

    if (desglose.saldoAnterior > 0) {
      if (deudasAnteriores.isNotEmpty) {
        for (final d in deudasAnteriores) {
          lineas.add(
            'Deuda anterior (Partido ${formatFechaCorta(d.fecha)}) '
            '${formatMoney(d.montoPendiente)}',
          );
        }
      } else {
        lineas.add(
          'Deuda anterior ${formatMoney(desglose.saldoAnterior)}',
        );
      }
    } else if (desglose.saldoAnterior < 0) {
      lineas.add(
        'Saldo a favor anterior: ${formatMoney(-desglose.saldoAnterior)}',
      );
    }

    if (desglose.pagado) {
      if (desglose.generaSaldoAFavor) {
        lineas.add(
          '✅ Al día — Saldo a favor: ${formatMoney(-desglose.saldoRestante)}',
        );
      } else if (desglose.montoPagado > 0) {
        lineas.add('💵 Pagaste: ${formatMoney(desglose.montoPagado)}');
      }
    } else {
      if (desglose.montoPagado > 0) {
        lineas.add('💵 Pagaste: ${formatMoney(desglose.montoPagado)}');
      }
      lineas.add(
        '💰 Total pendiente: *${formatMoney(desglose.saldoRestante)}*',
      );
    }

    lineas.addAll(
      _lineasTransferencia(titular, banco, cuenta, titulo: 'Transferencia'),
    );

    lineas.add('');
    lineas.addAll(
      desglose.pagado ? _lineasCierreAlDia : _lineasCierrePendiente,
    );

    return lineas.join('\n');
  }

  /// Mensaje simple cuando no hay desglose disponible.
  static String construirRecordatorio({
    required String nombreJugador,
    required double saldo,
    required List<DeudaPartidoAnterior> partidos,
    required String titular,
    required String banco,
    required String cuenta,
  }) {
    final lineas = <String>[
      '🎾 *Recordatorio Pádel Cobro*',
      '',
      'Hola ${formatNombreSaludo(nombreJugador)}!',
      '',
      'Tienes un saldo pendiente de *${formatMoney(saldo)}*.',
    ];

    if (partidos.isNotEmpty) {
      lineas
        ..add('')
        ..add('*Partidos pendientes:*');
      for (final p in partidos) {
        final f = formatFecha(p.fecha);
        final r = p.recinto?.trim();
        final linea = r != null && r.isNotEmpty ? '$f - $r' : f;
        lineas.add('• $linea: ${formatMoney(p.montoPendiente)}');
      }
    }

    lineas.addAll(
      _lineasTransferencia(
        titular,
        banco,
        cuenta,
        titulo: 'Datos para transferir',
      ),
    );

    lineas
      ..add('')
      ..addAll(_lineasCierrePendiente);

    return lineas.join('\n');
  }

  static List<String> _lineasTransferencia(
    String titular,
    String banco,
    String cuenta, {
    required String titulo,
  }) {
    if (titular.trim().isEmpty) return [];

    final lineas = <String>[
      '',
      '*$titulo:*',
      'Titular: $titular',
    ];
    if (banco.trim().isNotEmpty) lineas.add('Banco: $banco');
    if (cuenta.trim().isNotEmpty) lineas.add('Cuenta: $cuenta');
    return lineas;
  }

  static const _lineasCierrePendiente = [
    'Cuando puedas nos transfieres y quedamos al día 🙌',
    '¡Nos vemos en la cancha! 🎾🔥',
  ];

  static const _lineasCierreAlDia = [
    '¡Gracias por estar al día! 🙌',
    '¡Nos vemos en la cancha! 🎾🔥',
  ];
}
