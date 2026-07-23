import '../core/sport_type.dart';
import '../models/comprobante_estado.dart';
import '../models/convocatoria_jugador.dart';
import '../models/cobros_resumen.dart';
import '../models/costo_variable.dart';
import '../models/desglose_jugador.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/estadisticas_jugador.dart';
import '../models/saldo_historico.dart';
import '../models/detalle_partido.dart';
import '../models/estado_partido.dart' show EstadoConfirmacion;
import '../models/jugador.dart';
import '../models/cuenta_saldo.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';
import '../repositories/partido_repository.dart';

Map<String, dynamic> cobrosResumenToJson(CobrosResumen r) => {
      'montoTotalPendiente': r.montoTotalPendiente,
      'jugadoresConDeuda': r.jugadoresConDeuda,
    };

CobrosResumen cobrosResumenFromJson(Map<String, dynamic> json) => CobrosResumen(
      montoTotalPendiente:
          (json['montoTotalPendiente'] as num?)?.toDouble() ?? 0,
      jugadoresConDeuda: (json['jugadoresConDeuda'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> cuentaSaldoToJson(CuentaSaldo c) => {
      'organizador_id': c.organizadorId,
      'nombre': c.nombreOrganizador,
      'foto_url': c.fotoUrl,
      'saldo_acumulado': c.saldoAcumulado,
      'activo': c.activo,
      'left_at': c.leftAt?.toIso8601String(),
    };

CuentaSaldo cuentaSaldoFromJson(Map<String, dynamic> json) =>
    CuentaSaldo.fromJson(json);

Map<String, dynamic> jugadorToSnapshotJson(Jugador j) => {
      ...j.toMap(),
      'supabase_id': j.supabaseId,
      'foto_url': j.fotoUrl,
      'fcm_token': j.fcmToken,
      'app_last_seen_at': j.appLastSeenAt?.toIso8601String(),
    };

Jugador jugadorFromSnapshotJson(Map<String, dynamic> json) {
  final base = Jugador.fromMap(json);
  final seenRaw = json['app_last_seen_at'] as String?;
  return base.copyWith(
    supabaseId: json['supabase_id'] as String? ?? base.supabaseId,
    fotoUrl: json['foto_url'] as String? ?? base.fotoUrl,
    fcmToken: json['fcm_token'] as String? ?? base.fcmToken,
    appLastSeenAt:
        seenRaw == null ? base.appLastSeenAt : DateTime.tryParse(seenRaw),
  );
}

Map<String, dynamic> resumenJugadorToJson(ResumenJugador r) => {
      'jugador': jugadorToSnapshotJson(r.jugador),
      'saldoActual': r.saldoActual,
      'partidosJugados': r.partidosJugados,
      'totalPendiente': r.totalPendiente,
    };

ResumenJugador resumenJugadorFromJson(Map<String, dynamic> json) =>
    ResumenJugador(
      jugador: jugadorFromSnapshotJson(
        Map<String, dynamic>.from(json['jugador'] as Map),
      ),
      saldoActual: (json['saldoActual'] as num?)?.toDouble() ?? 0,
      partidosJugados: (json['partidosJugados'] as num?)?.toInt() ?? 0,
      totalPendiente: (json['totalPendiente'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> partidoToSnapshotJson(Partido p) => p.toMap();

Partido partidoFromSnapshotJson(Map<String, dynamic> json) =>
    Partido.fromMap(json);

Map<String, dynamic> detallePartidoToJson(DetallePartido d) => {
      'id': d.id,
      'partido_id': d.partidoId,
      'jugador_id': d.jugadorId,
      'jugador_supabase_id': d.jugadorSupabaseId,
      'asistio': d.asistio,
      'prorrateo_fijo': d.prorrateoFijo,
      'total_variables': d.totalVariables,
      'total': d.total,
      'pagado': d.pagado,
      'monto_pagado': d.montoPagado,
      'comprobante_url': d.comprobanteUrl,
      'comprobante_validado': d.comprobanteValidado,
      'comprobante_estado': d.comprobanteEstado?.dbValue,
      'monto_pago_declarado': d.montoPagoDeclarado,
      'pago_es_abono': d.pagoEsAbono,
      'nombre_jugador': d.nombreJugador,
      'fecha_partido': d.fechaPartido?.toIso8601String(),
      'recinto_partido': d.recintoPartido,
      'sport_type': d.sportType?.dbValue,
      'organizador_id': d.organizadorId,
    };

DetallePartido detallePartidoFromJson(Map<String, dynamic> json) =>
    DetallePartido(
      id: json['id'] as int?,
      partidoId: json['partido_id'] as int,
      jugadorId: (json['jugador_id'] as num?)?.toInt() ?? 0,
      jugadorSupabaseId: json['jugador_supabase_id'] as String?,
      asistio: json['asistio'] as bool? ?? true,
      prorrateoFijo: (json['prorrateo_fijo'] as num?)?.toDouble() ?? 0,
      totalVariables: (json['total_variables'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      pagado: json['pagado'] as bool? ?? false,
      montoPagado: (json['monto_pagado'] as num?)?.toDouble() ?? 0,
      comprobanteUrl: json['comprobante_url'] as String?,
      comprobanteValidado: json['comprobante_validado'] as bool?,
      comprobanteEstado: ComprobanteEstado.fromDb(
        json['comprobante_estado'] as String?,
      ),
      montoPagoDeclarado: (json['monto_pago_declarado'] as num?)?.toDouble(),
      pagoEsAbono: json['pago_es_abono'] as bool?,
      nombreJugador: json['nombre_jugador'] as String?,
      fechaPartido: json['fecha_partido'] != null
          ? DateTime.tryParse(json['fecha_partido'] as String)
          : null,
      recintoPartido: json['recinto_partido'] as String?,
      sportType: json['sport_type'] != null
          ? SportType.fromDb(json['sport_type'] as String?)
          : null,
      organizadorId: json['organizador_id'] as String?,
    );

Map<String, dynamic> convocatoriaEntryToJson(ConvocatoriaJugadorEntry e) => {
      'id': e.id,
      'partido_id': e.partidoId,
      'jugador': jugadorToSnapshotJson(e.jugador),
      'estado': e.estado.dbValue,
      'es_suplente': e.esSuplente,
      'orden_espera': e.ordenEspera,
      'tiempo_limite': e.tiempoLimite?.toIso8601String(),
      'notificado_vencimiento': e.notificadoVencimiento,
      'recordatorio_plazo_enviado': e.recordatorioPlazoEnviado,
    };

ConvocatoriaJugadorEntry convocatoriaEntryFromJson(Map<String, dynamic> json) =>
    ConvocatoriaJugadorEntry(
      id: json['id'] as int?,
      partidoId: json['partido_id'] as int,
      jugador: jugadorFromSnapshotJson(
        Map<String, dynamic>.from(json['jugador'] as Map),
      ),
      estado: EstadoConfirmacion.fromDb(json['estado'] as String?),
      esSuplente: json['es_suplente'] as bool? ?? false,
      ordenEspera: json['orden_espera'] as int?,
      tiempoLimite: json['tiempo_limite'] != null
          ? DateTime.tryParse(json['tiempo_limite'] as String)
          : null,
      notificadoVencimiento: json['notificado_vencimiento'] as bool? ?? false,
      recordatorioPlazoEnviado:
          json['recordatorio_plazo_enviado'] as bool? ?? false,
    );

Map<String, dynamic> convocatoriaCompletaToJson(ConvocatoriaCompleta c) => {
      'partido': partidoToSnapshotJson(c.partido),
      'jugadores': c.jugadores.map(convocatoriaEntryToJson).toList(),
    };

ConvocatoriaCompleta convocatoriaCompletaFromJson(Map<String, dynamic> json) =>
    ConvocatoriaCompleta(
      partido: partidoFromSnapshotJson(
        Map<String, dynamic>.from(json['partido'] as Map),
      ),
      jugadores: (json['jugadores'] as List? ?? const [])
          .map((e) => convocatoriaEntryFromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );

Map<String, dynamic> miConvocatoriaToJson(MiConvocatoria m) => {
      'entry': convocatoriaEntryToJson(m.entry),
      'partido': partidoToSnapshotJson(m.partido),
    };

MiConvocatoria miConvocatoriaFromJson(Map<String, dynamic> json) =>
    MiConvocatoria(
      entry: convocatoriaEntryFromJson(
        Map<String, dynamic>.from(json['entry'] as Map),
      ),
      partido: partidoFromSnapshotJson(
        Map<String, dynamic>.from(json['partido'] as Map),
      ),
    );

Map<String, dynamic> costoVariableToJson(CostoVariable c) => c.toMap();

CostoVariable costoVariableFromJson(Map<String, dynamic> json) =>
    CostoVariable.fromMap(json);

Map<String, dynamic> asignacionCostoToJson(AsignacionCostoVariable a) => {
      ...a.toMap(),
      'jugador_supabase_id': a.jugadorSupabaseId,
    };

AsignacionCostoVariable asignacionCostoFromJson(Map<String, dynamic> json) =>
    AsignacionCostoVariable(
      id: json['id'] as int?,
      costoVariableId: json['costo_variable_id'] as int,
      jugadorId: (json['jugador_id'] as num?)?.toInt() ?? 0,
      jugadorSupabaseId: json['jugador_supabase_id'] as String?,
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> partidoCompletoToJson(PartidoCompleto p) => {
      'partido': partidoToSnapshotJson(p.partido),
      'detalles': p.detalles.map(detallePartidoToJson).toList(),
      'costosVariables': p.costosVariables.map(costoVariableToJson).toList(),
      'asignacionesPorCosto': p.asignacionesPorCosto.map(
        (costoId, list) => MapEntry(
          costoId.toString(),
          list.map(asignacionCostoToJson).toList(),
        ),
      ),
      'saldoAnteriorPorJugador': p.saldoAnteriorPorJugador,
      'saldoCuentaPorJugador': p.saldoCuentaPorJugador,
    };

PartidoCompleto partidoCompletoFromJson(Map<String, dynamic> json) {
  final asignRaw = json['asignacionesPorCosto'] as Map? ?? const {};
  final asignaciones = <int, List<AsignacionCostoVariable>>{};
  for (final entry in asignRaw.entries) {
    final costoId = int.parse(entry.key.toString());
    final list = (entry.value as List? ?? const [])
        .map((e) => asignacionCostoFromJson(Map<String, dynamic>.from(e)))
        .toList();
    asignaciones[costoId] = list;
  }
  final saldoRaw = json['saldoAnteriorPorJugador'] as Map? ?? const {};
  final cuentaRaw = json['saldoCuentaPorJugador'] as Map? ?? const {};
  return PartidoCompleto(
    partido: partidoFromSnapshotJson(
      Map<String, dynamic>.from(json['partido'] as Map),
    ),
    detalles: (json['detalles'] as List? ?? const [])
        .map((e) => detallePartidoFromJson(Map<String, dynamic>.from(e)))
        .toList(),
    costosVariables: (json['costosVariables'] as List? ?? const [])
        .map((e) => costoVariableFromJson(Map<String, dynamic>.from(e)))
        .toList(),
    asignacionesPorCosto: asignaciones,
    saldoAnteriorPorJugador: saldoRaw.map(
      (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
    ),
    saldoCuentaPorJugador: cuentaRaw.map(
      (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
    ),
  );
}

Map<String, dynamic> desgloseJugadorToJson(DesgloseJugador d) => {
      'jugadorId': d.jugadorId,
      'jugadorSupabaseId': d.jugadorSupabaseId,
      'nombre': d.nombre,
      'saldoAnterior': d.saldoAnterior,
      'cancha': d.cancha,
      'pelotas': d.pelotas,
      'variables': d.variables,
      'totalPartido': d.totalPartido,
      'totalDebido': d.totalDebido,
      'montoPagado': d.montoPagado,
      'saldoRestante': d.saldoRestante,
      'pagado': d.pagado,
      'saldoAcumuladoCuenta': d.saldoAcumuladoCuenta,
    };

DesgloseJugador desgloseJugadorFromJson(Map<String, dynamic> json) =>
    DesgloseJugador(
      jugadorId: (json['jugadorId'] as num?)?.toInt() ?? 0,
      jugadorSupabaseId: json['jugadorSupabaseId'] as String?,
      nombre: json['nombre'] as String? ?? '',
      saldoAnterior: (json['saldoAnterior'] as num?)?.toDouble() ?? 0,
      cancha: (json['cancha'] as num?)?.toDouble() ?? 0,
      pelotas: (json['pelotas'] as num?)?.toDouble() ?? 0,
      variables: (json['variables'] as Map? ?? const {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      ),
      totalPartido: (json['totalPartido'] as num?)?.toDouble() ?? 0,
      totalDebido: (json['totalDebido'] as num?)?.toDouble() ?? 0,
      montoPagado: (json['montoPagado'] as num?)?.toDouble() ?? 0,
      saldoRestante: (json['saldoRestante'] as num?)?.toDouble() ?? 0,
      pagado: json['pagado'] as bool? ?? false,
      saldoAcumuladoCuenta: (json['saldoAcumuladoCuenta'] as num?)?.toDouble(),
    );

Map<String, dynamic> saldoHistoricoToJson(SaldoHistorico h) => {
      ...h.toMap(),
      'jugador_supabase_id': h.jugadorSupabaseId,
      'nombre_jugador': h.nombreJugador,
    };

SaldoHistorico saldoHistoricoFromJson(Map<String, dynamic> json) {
  final base = SaldoHistorico.fromMap(json);
  return SaldoHistorico(
    id: base.id,
    jugadorId: base.jugadorId,
    jugadorSupabaseId:
        json['jugador_supabase_id'] as String? ?? base.jugadorSupabaseId,
    partidoId: base.partidoId,
    saldoAnterior: base.saldoAnterior,
    cargoPartido: base.cargoPartido,
    abono: base.abono,
    saldoNuevo: base.saldoNuevo,
    fecha: base.fecha,
    concepto: base.concepto,
    nombreJugador: json['nombre_jugador'] as String? ?? base.nombreJugador,
    organizadorId: json['organizador_id'] as String? ?? base.organizadorId,
  );
}

Map<String, dynamic> deudaPartidoAnteriorToJson(DeudaPartidoAnterior d) => {
      'partido_id': d.partidoId,
      'fecha': d.fecha.toIso8601String(),
      'recinto': d.recinto,
      'pendiente_neto': d.pendienteNeto,
      'sport_type': d.sportType.dbValue,
    };

DeudaPartidoAnterior deudaPartidoAnteriorFromJson(Map<String, dynamic> json) =>
    DeudaPartidoAnterior(
      partidoId: json['partido_id'] as int,
      fecha: DateTime.parse(json['fecha'] as String),
      recinto: json['recinto'] as String?,
      pendienteNeto: (json['pendiente_neto'] as num?)?.toDouble() ?? 0,
      sportType: SportType.fromDb(json['sport_type'] as String?),
    );

Map<String, dynamic> estadisticasJugadorToJson(EstadisticasJugador e) => {
      'jugador_id': e.jugadorId,
      'jugador_key_id': e.jugadorKeyId,
      'nombre': e.nombre,
      'foto_path': e.fotoPath,
      'foto_url': e.fotoUrl,
      'partidos_jugados': e.partidosJugados,
      'pagos_al_dia': e.pagosAlDia,
      'pagos_tardios': e.pagosTardios,
      'partidos_impagos': e.partidosImpagos,
      'promedio_dias_pago': e.promedioDiasPago,
      'total_gastado': e.totalGastado,
      'saldo_actual': e.saldoActual,
      'convocatorias_confirmadas': e.convocatoriasConfirmadas,
      'partidos_ultimos_90_dias': e.partidosUltimos90Dias,
    };

EstadisticasJugador estadisticasJugadorFromJson(Map<String, dynamic> json) =>
    EstadisticasJugador(
      jugadorId: (json['jugador_id'] as num?)?.toInt() ?? 0,
      jugadorKeyId: json['jugador_key_id'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      fotoPath: json['foto_path'] as String?,
      fotoUrl: json['foto_url'] as String?,
      partidosJugados: (json['partidos_jugados'] as num?)?.toInt() ?? 0,
      pagosAlDia: (json['pagos_al_dia'] as num?)?.toInt() ?? 0,
      pagosTardios: (json['pagos_tardios'] as num?)?.toInt() ?? 0,
      partidosImpagos: (json['partidos_impagos'] as num?)?.toInt() ?? 0,
      promedioDiasPago: (json['promedio_dias_pago'] as num?)?.toDouble() ?? 0,
      totalGastado: (json['total_gastado'] as num?)?.toDouble() ?? 0,
      saldoActual: (json['saldo_actual'] as num?)?.toDouble() ?? 0,
      convocatoriasConfirmadas:
          (json['convocatorias_confirmadas'] as num?)?.toInt() ?? 0,
      partidosUltimos90Dias:
          (json['partidos_ultimos_90_dias'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> resumenPartidosJugadorToJson(
  ({int partidosJugados, int partidosPagados, int partidosImpagos}) r,
) =>
    {
      'partidosJugados': r.partidosJugados,
      'partidosPagados': r.partidosPagados,
      'partidosImpagos': r.partidosImpagos,
    };

({int partidosJugados, int partidosPagados, int partidosImpagos})
    resumenPartidosJugadorFromJson(Map<String, dynamic> json) => (
      partidosJugados: (json['partidosJugados'] as num?)?.toInt() ?? 0,
      partidosPagados: (json['partidosPagados'] as num?)?.toInt() ?? 0,
      partidosImpagos: (json['partidosImpagos'] as num?)?.toInt() ?? 0,
    );
