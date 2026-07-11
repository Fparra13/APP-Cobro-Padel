import '../core/sport_type.dart';
import 'detalle_partido.dart';
import 'mi_convocatoria.dart';

/// Fila del historial del jugador: partido jugado o convocatoria cancelada.
class PlayerHistorialEntry {
  final DetallePartido? jugado;
  final MiConvocatoria? cancelado;

  const PlayerHistorialEntry._({this.jugado, this.cancelado});

  const PlayerHistorialEntry.jugado(DetallePartido detalle)
      : this._(jugado: detalle);

  const PlayerHistorialEntry.cancelado(MiConvocatoria convocatoria)
      : this._(cancelado: convocatoria);

  bool get esCancelado => cancelado != null;

  int get partidoId =>
      jugado?.partidoId ?? cancelado!.partido.id ?? cancelado!.entry.partidoId;

  DateTime? get fecha =>
      jugado?.fechaPartido ?? cancelado?.partido.fecha;

  DateTime get fechaOrden {
    if (cancelado != null) {
      final p = cancelado!.partido;
      return p.resueltoEn ?? p.fecha;
    }
    return jugado!.fechaPartido ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  SportType? get sportType =>
      jugado?.sportType ?? cancelado?.partido.sportType;

  static List<PlayerHistorialEntry> merge({
    required List<DetallePartido> jugados,
    required List<MiConvocatoria> cancelados,
  }) {
    final entries = <PlayerHistorialEntry>[
      ...jugados.map(PlayerHistorialEntry.jugado),
      ...cancelados.map(PlayerHistorialEntry.cancelado),
    ];
    entries.sort((a, b) => b.fechaOrden.compareTo(a.fechaOrden));
    return entries;
  }
}
