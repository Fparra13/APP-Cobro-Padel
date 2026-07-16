import '../core/sport_type.dart';
import '../core/supabase_parse.dart';
import '../domain/cobro_logic.dart';
import 'comprobante_estado.dart';

class DetallePartido {
  final int? id;
  final int partidoId;
  final int jugadorId;
  /// UUID del jugador en Supabase.
  final String? jugadorSupabaseId;
  final bool asistio;
  final double prorrateoFijo;
  final double totalVariables;
  final double total;
  final bool pagado;
  final double montoPagado;
  final String? comprobanteUrl;
  final bool? comprobanteValidado;
  /// Estado explícito: en revisión / aprobado / rechazado.
  final ComprobanteEstado? comprobanteEstado;
  final double? montoPagoDeclarado;
  final bool? pagoEsAbono;
  final String? nombreJugador;
  final DateTime? fechaPartido;
  final String? recintoPartido;
  final SportType? sportType;
  /// Organizador dueño del partido (cuenta de cobro). Null solo en datos legacy.
  final String? organizadorId;

  const DetallePartido({
    this.id,
    required this.partidoId,
    this.jugadorId = 0,
    this.jugadorSupabaseId,
    this.asistio = true,
    this.prorrateoFijo = 0,
    this.totalVariables = 0,
    this.total = 0,
    this.pagado = false,
    this.montoPagado = 0,
    this.comprobanteUrl,
    this.comprobanteValidado,
    this.comprobanteEstado,
    this.montoPagoDeclarado,
    this.pagoEsAbono,
    this.nombreJugador,
    this.fechaPartido,
    this.recintoPartido,
    this.sportType,
    this.organizadorId,
  });

  /// @deprecated Usar [pagoParcialNeto].
  @Deprecated('Usar estadoCobro(snapshot).pagoParcial')
  bool get pagoParcialLegacy => montoPagado > 0 && !pagado;

  ComprobanteEstado? get comprobanteEstadoEfectivo =>
      comprobanteEstado ??
      ComprobanteEstado.fromLegacy(
        comprobanteValidado: comprobanteValidado,
        comprobanteUrl: comprobanteUrl,
        montoPagoDeclarado: montoPagoDeclarado,
      );

  /// Pago/abono declarado por el jugador, aún no validado por el organizador.
  bool get comprobantePendienteValidacion =>
      comprobanteEstadoEfectivo == ComprobanteEstado.enRevision;

  /// Hay archivo en Storage/DB y ya no está en cola de validación.
  bool get comprobanteEsHistorico {
    final url = comprobanteUrl?.trim() ?? '';
    if (url.isEmpty) return false;
    final e = comprobanteEstadoEfectivo;
    return e == ComprobanteEstado.aprobado || e == ComprobanteEstado.rechazado;
  }

  bool get tieneComprobanteArchivo {
    final url = comprobanteUrl?.trim() ?? '';
    return url.isNotEmpty;
  }

  /// @deprecated Usar [CobroLogic.obtenerPendientePartido]. Bruto: ignora crédito.
  @Deprecated('Usar CobroLogic.obtenerPendientePartido(...)')
  double get montoPendiente {
    final restante = total - montoPagado;
    if (restante <= 0.005) return 0;
    return restante;
  }

  /// Pendiente neto cuando se conoce el saldo anterior al partido.
  double pendienteNeto({required double saldoAnteriorAlPartido}) =>
      CobroLogic.obtenerPendientePartido(
        saldoAnteriorAlPartido: saldoAnteriorAlPartido,
        cargoPartido: total,
        montoPagadoEnPartido: montoPagado,
      );

  /// Estado de cobro con snapshot obligatorio.
  EstadoPagoDetalle estadoCobro({required double? snapshotSaldoAnterior}) =>
      CobroLogic.estadoPagoDetalle(
        partidoId: partidoId,
        jugadorId: jugadorKeyId,
        cargoPartido: total,
        montoPagadoEnPartido: montoPagado,
        snapshotSaldoAnterior: snapshotSaldoAnterior,
      );

  bool tieneDeudaNeto({required double snapshotSaldoAnterior}) =>
      estadoCobro(snapshotSaldoAnterior: snapshotSaldoAnterior).tieneDeuda;

  bool pagoParcialNeto({required double snapshotSaldoAnterior}) =>
      estadoCobro(snapshotSaldoAnterior: snapshotSaldoAnterior).pagoParcial;

  bool partidoCerradoNeto({required double snapshotSaldoAnterior}) =>
      estadoCobro(snapshotSaldoAnterior: snapshotSaldoAnterior).partidoCerrado;

  /// @deprecated Usar [estadoCobro] / [tieneDeudaNeto]. Bruto: ignora crédito.
  @Deprecated('Usar estadoCobro(snapshot).tieneDeuda')
  bool get tieneDeudaEnCobro => !pagado && montoPendiente > 0.005;

  /// @deprecated Usar [estadoCobro] / [pagoParcialNeto].
  @Deprecated('Usar estadoCobro(snapshot).pagoParcial')
  bool get pagoParcial => pagoParcialLegacy;

  bool pendientePagoNeto({required double snapshotSaldoAnterior}) =>
      tieneDeudaNeto(snapshotSaldoAnterior: snapshotSaldoAnterior) &&
      !comprobantePendienteValidacion;

  /// @deprecated Usar [pendientePagoNeto].
  @Deprecated('Usar pendientePagoNeto(snapshot)')
  bool get pendientePago =>
      tieneDeudaEnCobro && !comprobantePendienteValidacion;

  bool get puedeDeclararPago => !comprobantePendienteValidacion;

  String get jugadorKeyId =>
      jugadorSupabaseId ?? (jugadorId > 0 ? jugadorId.toString() : '');

  DetallePartido copyWith({
    int? id,
    int? partidoId,
    int? jugadorId,
    String? jugadorSupabaseId,
    bool? asistio,
    double? prorrateoFijo,
    double? totalVariables,
    double? total,
    bool? pagado,
    double? montoPagado,
    String? comprobanteUrl,
    bool? comprobanteValidado,
    ComprobanteEstado? comprobanteEstado,
    double? montoPagoDeclarado,
    bool? pagoEsAbono,
    String? nombreJugador,
    DateTime? fechaPartido,
    String? recintoPartido,
    SportType? sportType,
    String? organizadorId,
  }) {
    return DetallePartido(
      id: id ?? this.id,
      partidoId: partidoId ?? this.partidoId,
      jugadorId: jugadorId ?? this.jugadorId,
      jugadorSupabaseId: jugadorSupabaseId ?? this.jugadorSupabaseId,
      asistio: asistio ?? this.asistio,
      prorrateoFijo: prorrateoFijo ?? this.prorrateoFijo,
      totalVariables: totalVariables ?? this.totalVariables,
      total: total ?? this.total,
      pagado: pagado ?? this.pagado,
      montoPagado: montoPagado ?? this.montoPagado,
      comprobanteUrl: comprobanteUrl ?? this.comprobanteUrl,
      comprobanteValidado: comprobanteValidado ?? this.comprobanteValidado,
      comprobanteEstado: comprobanteEstado ?? this.comprobanteEstado,
      montoPagoDeclarado: montoPagoDeclarado ?? this.montoPagoDeclarado,
      pagoEsAbono: pagoEsAbono ?? this.pagoEsAbono,
      nombreJugador: nombreJugador ?? this.nombreJugador,
      fechaPartido: fechaPartido ?? this.fechaPartido,
      recintoPartido: recintoPartido ?? this.recintoPartido,
      sportType: sportType ?? this.sportType,
      organizadorId: organizadorId ?? this.organizadorId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'partido_id': partidoId,
        'jugador_id': jugadorId,
        'asistio': asistio ? 1 : 0,
        'prorrateo_fijo': prorrateoFijo,
        'total_variables': totalVariables,
        'total': total,
        'pagado': pagado ? 1 : 0,
        'monto_pagado': montoPagado,
      };

  factory DetallePartido.fromMap(Map<String, dynamic> map) => DetallePartido(
        id: map['id'] as int?,
        partidoId: map['partido_id'] as int,
        jugadorId: map['jugador_id'] as int,
        asistio: (map['asistio'] as int? ?? 1) == 1,
        prorrateoFijo: (map['prorrateo_fijo'] as num?)?.toDouble() ?? 0,
        totalVariables: (map['total_variables'] as num?)?.toDouble() ?? 0,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        pagado: (map['pagado'] as int? ?? 0) == 1,
        montoPagado: (map['monto_pagado'] as num?)?.toDouble() ?? 0,
        nombreJugador: map['nombre_jugador'] as String?,
      );

  factory DetallePartido.fromSupabaseMap(
    Map<String, dynamic> map, {
    String? nombreJugador,
    DateTime? fechaPartido,
    String? recintoPartido,
    SportType? sportType,
    String? organizadorId,
  }) {
    final url = SupabaseParse.toStringOrNull(map['comprobante_url']);
    final validado = map['comprobante_validado'] as bool?;
    final declarado = (map['monto_pago_declarado'] as num?)?.toDouble();
    final estado = ComprobanteEstado.fromDb(
          SupabaseParse.toStringOrNull(map['comprobante_estado']),
        ) ??
        ComprobanteEstado.fromLegacy(
          comprobanteValidado: validado,
          comprobanteUrl: url,
          montoPagoDeclarado: declarado,
        );
    return DetallePartido(
      id: (map['id'] as num?)?.toInt(),
      partidoId: (map['partido_id'] as num).toInt(),
      jugadorSupabaseId: SupabaseParse.toStringOrNull(map['jugador_id']),
      asistio: map['asistio'] as bool? ?? true,
      prorrateoFijo: (map['prorrateo_fijo'] as num?)?.toDouble() ?? 0,
      totalVariables: (map['total_variables'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      pagado: map['pagado'] as bool? ?? false,
      montoPagado: (map['monto_pagado'] as num?)?.toDouble() ?? 0,
      comprobanteUrl: url,
      comprobanteValidado: validado,
      comprobanteEstado: estado,
      montoPagoDeclarado: declarado,
      pagoEsAbono: map['pago_es_abono'] as bool?,
      nombreJugador: nombreJugador,
      fechaPartido: fechaPartido,
      recintoPartido: recintoPartido,
      sportType: sportType,
      organizadorId: organizadorId ??
          SupabaseParse.toStringOrNull(map['organizador_id']) ??
          SupabaseParse.toStringOrNull(map['partido_organizador_id']),
    );
  }
}
