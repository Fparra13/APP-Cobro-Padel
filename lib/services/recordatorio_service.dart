import '../models/deuda_partido_anterior.dart';
import '../models/desglose_jugador.dart';
import '../models/jugador.dart';
import '../repositories/partido_repository.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/preferences_service.dart';
import '../services/share_service.dart';

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

    if (partidos.isNotEmpty) {
      for (var i = partidos.length - 1; i >= 0; i--) {
        final detallado = await _construirMensajeDetallado(
          jugador: jugador,
          partidoPendiente: partidos[i],
          titular: titular,
          banco: banco,
          cuenta: cuenta,
        );
        if (detallado.isNotEmpty) return detallado;
      }
    }

    return MensajeCobroService.construirRecordatorio(
      nombreJugador: jugador.nombre,
      saldo: saldo,
      partidos: partidos,
      titular: titular,
      banco: banco,
      cuenta: cuenta,
    );
  }

  Future<String> _construirMensajeDetallado({
    required Jugador jugador,
    required DeudaPartidoAnterior partidoPendiente,
    required String titular,
    required String banco,
    required String cuenta,
  }) async {
    final completo = await _partidoRepo.getCompleto(partidoPendiente.partidoId);
    if (completo == null) return '';

    final desgloseList =
        await _partidoRepo.getDesglose(partidoPendiente.partidoId);
    DesgloseJugador? desglose;
    for (final d in desgloseList) {
      if (d.jugadorId == jugador.id) {
        desglose = d;
        break;
      }
    }
    if (desglose == null) return '';

    final deudasAnteriores = await _partidoRepo.getDeudasPartidosAnteriores(
      jugadorId: jugador.id!,
      partidoActualId: partidoPendiente.partidoId,
    );

    return MensajeCobroService.construirDetallePartido(
      partido: completo.partido,
      desglose: desglose,
      deudasAnteriores: deudasAnteriores,
      titular: titular,
      banco: banco,
      cuenta: cuenta,
    );
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
