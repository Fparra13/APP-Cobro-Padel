import '../core/supabase_parse.dart';

class SaldoHistorico {
  final int? id;
  final int jugadorId;
  final String? jugadorSupabaseId;
  final int? partidoId;
  final double saldoAnterior;
  final double cargoPartido;
  final double abono;
  final double saldoNuevo;
  final DateTime fecha;
  final String concepto;
  final String? nombreJugador;

  const SaldoHistorico({
    this.id,
    this.jugadorId = 0,
    this.jugadorSupabaseId,
    this.partidoId,
    required this.saldoAnterior,
    required this.cargoPartido,
    required this.abono,
    required this.saldoNuevo,
    required this.fecha,
    required this.concepto,
    this.nombreJugador,
  });

  String get jugadorKeyId =>
      jugadorSupabaseId ?? (jugadorId > 0 ? jugadorId.toString() : '');

  Map<String, dynamic> toMap() => {
        'id': id,
        'jugador_id': jugadorId,
        'partido_id': partidoId,
        'saldo_anterior': saldoAnterior,
        'cargo_partido': cargoPartido,
        'abono': abono,
        'saldo_nuevo': saldoNuevo,
        'fecha': fecha.toIso8601String(),
        'concepto': concepto,
      };

  factory SaldoHistorico.fromMap(Map<String, dynamic> map) => SaldoHistorico(
        id: map['id'] as int?,
        jugadorId: map['jugador_id'] as int,
        partidoId: map['partido_id'] as int?,
        saldoAnterior: (map['saldo_anterior'] as num).toDouble(),
        cargoPartido: (map['cargo_partido'] as num).toDouble(),
        abono: (map['abono'] as num).toDouble(),
        saldoNuevo: (map['saldo_nuevo'] as num).toDouble(),
        fecha: DateTime.parse(map['fecha'] as String),
        concepto: map['concepto'] as String,
        nombreJugador: map['nombre_jugador'] as String?,
      );

  factory SaldoHistorico.fromSupabaseMap(Map<String, dynamic> map) =>
      SaldoHistorico(
        id: map['id'] is num ? (map['id'] as num).toInt() : null,
        jugadorSupabaseId: SupabaseParse.toStringOrNull(map['jugador_id']),
        partidoId: map['partido_id'] is num
            ? (map['partido_id'] as num).toInt()
            : null,
        saldoAnterior: SupabaseParse.toDouble(map['saldo_anterior']),
        cargoPartido: SupabaseParse.toDouble(map['cargo_partido']),
        abono: SupabaseParse.toDouble(map['abono']),
        saldoNuevo: SupabaseParse.toDouble(map['saldo_nuevo']),
        fecha: SupabaseParse.toDateTime(map['fecha']),
        concepto: SupabaseParse.asString(map['concepto'], fallback: 'Movimiento'),
        nombreJugador: SupabaseParse.toStringOrNull(map['nombre_jugador']),
      );
}
