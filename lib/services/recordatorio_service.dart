import 'package:intl/intl.dart';

import '../models/deuda_partido_anterior.dart';
import '../models/jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/preferences_service.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart';

class RecordatorioResultado {
  final int enviados;
  final int sinTelefono;
  final int errores;

  const RecordatorioResultado({
    required this.enviados,
    required this.sinTelefono,
    required this.errores,
  });
}

class RecordatorioService {
  final _prefs = PreferencesService();
  final _share = ShareService();
  final _partidoRepo = PartidoRepository();

  String _fmt(double v) => formatMoney(v);

  String _lineaPartido(DateTime fecha, String? recinto) {
    final f = DateFormat('dd/MM/yyyy').format(fecha);
    final r = recinto?.trim();
    if (r != null && r.isNotEmpty) return '$f - $r';
    return f;
  }

  Future<String> construirMensaje({
    required Jugador jugador,
    required double saldo,
    List<DeudaPartidoAnterior>? partidosPendientes,
  }) async {
    final titular = await _prefs.titularNombre;
    final banco = await _prefs.bancoNombre;
    final cuenta = await _prefs.cuentaNumero;

    final partidos = partidosPendientes ??
        await _partidoRepo.getPartidosPendientesJugador(jugador.id!);

    final buffer = StringBuffer()
      ..writeln('🎾 *Recordatorio Pádel Cobro*')
      ..writeln('')
      ..writeln('Hola ${jugador.nombre}!')
      ..writeln('')
      ..writeln('Tienes un saldo pendiente de *${_fmt(saldo)}*.');

    if (partidos.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('*Partidos pendientes:*');
      for (final p in partidos) {
        buffer.writeln(
          '• ${_lineaPartido(p.fecha, p.recinto)}: ${_fmt(p.montoPendiente)}',
        );
      }
    }

    if (titular.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('*Datos para transferir:*')
        ..writeln('Titular: $titular');
      if (banco.isNotEmpty) buffer.writeln('Banco: $banco');
      if (cuenta.isNotEmpty) buffer.writeln('Cuenta: $cuenta');
    }

    buffer.writeln('');
    buffer.writeln('¡Gracias! 🙌');
    return buffer.toString();
  }

  Future<void> enviarIndividual({
    required Jugador jugador,
    required double saldo,
  }) async {
    final mensaje = await construirMensaje(jugador: jugador, saldo: saldo);
    await _share.compartirWhatsApp(
      mensaje: mensaje,
      telefono: jugador.telefono,
    );
  }

  Future<RecordatorioResultado> enviarATodos(
    List<ResumenJugador> resumenes,
  ) async {
    final deudores = resumenes.where((r) => r.saldoActual > 0).toList();
    var enviados = 0;
    var sinTelefono = 0;
    var errores = 0;

    for (final r in deudores) {
      final tel = r.jugador.telefono?.trim() ?? '';
      if (tel.isEmpty) {
        sinTelefono++;
        continue;
      }
      try {
        await enviarIndividual(jugador: r.jugador, saldo: r.saldoActual);
        enviados++;
      } catch (_) {
        errores++;
      }
    }

    return RecordatorioResultado(
      enviados: enviados,
      sinTelefono: sinTelefono,
      errores: errores,
    );
  }
}
