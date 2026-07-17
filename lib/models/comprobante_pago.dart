import '../core/supabase_parse.dart';
import 'comprobante_estado.dart';

/// Una foto de pago/abono en el historial (no se pisa al reenviar).
class ComprobantePago {
  final int? id;
  final int detalleId;
  final int partidoId;
  final String jugadorId;
  final String organizadorId;
  final String storagePath;
  final double? montoDeclarado;
  final bool esAbono;
  final ComprobanteEstado estado;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const ComprobantePago({
    this.id,
    required this.detalleId,
    required this.partidoId,
    required this.jugadorId,
    required this.organizadorId,
    required this.storagePath,
    this.montoDeclarado,
    this.esAbono = false,
    required this.estado,
    this.createdAt,
    this.resolvedAt,
  });

  factory ComprobantePago.fromSupabaseMap(Map<String, dynamic> map) {
    final estado = ComprobanteEstado.fromDb(
          SupabaseParse.toStringOrNull(map['estado']),
        ) ??
        ComprobanteEstado.enRevision;
    return ComprobantePago(
      id: (map['id'] as num?)?.toInt(),
      detalleId: (map['detalle_id'] as num).toInt(),
      partidoId: (map['partido_id'] as num).toInt(),
      jugadorId: SupabaseParse.toStringOrNull(map['jugador_id']) ?? '',
      organizadorId: SupabaseParse.toStringOrNull(map['organizador_id']) ?? '',
      storagePath: SupabaseParse.toStringOrNull(map['storage_path']) ?? '',
      montoDeclarado: (map['monto_declarado'] as num?)?.toDouble(),
      esAbono: map['es_abono'] as bool? ?? false,
      estado: estado,
      createdAt: SupabaseParse.toDateTime(map['created_at']),
      resolvedAt: SupabaseParse.toDateTime(map['resolved_at']),
    );
  }
}
