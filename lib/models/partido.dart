class Partido {
  final int? id;
  final DateTime fecha;
  final double costoCancha;
  final double costoPelotas;
  final String? recinto;
  final String? notas;
  final String? comprobanteCancha;
  final String? comprobantePelotas;
  final DateTime createdAt;

  const Partido({
    this.id,
    required this.fecha,
    this.costoCancha = 0,
    this.costoPelotas = 0,
    this.recinto,
    this.notas,
    this.comprobanteCancha,
    this.comprobantePelotas,
    required this.createdAt,
  });

  double get costoFijoTotal => costoCancha + costoPelotas;

  Partido copyWith({
    int? id,
    DateTime? fecha,
    double? costoCancha,
    double? costoPelotas,
    String? recinto,
    String? notas,
    String? comprobanteCancha,
    String? comprobantePelotas,
    DateTime? createdAt,
  }) {
    return Partido(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      costoCancha: costoCancha ?? this.costoCancha,
      costoPelotas: costoPelotas ?? this.costoPelotas,
      recinto: recinto ?? this.recinto,
      notas: notas ?? this.notas,
      comprobanteCancha: comprobanteCancha ?? this.comprobanteCancha,
      comprobantePelotas: comprobantePelotas ?? this.comprobantePelotas,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fecha': fecha.toIso8601String(),
        'costo_cancha': costoCancha,
        'costo_pelotas': costoPelotas,
        'recinto': recinto,
        'notas': notas,
        'comprobante_cancha': comprobanteCancha,
        'comprobante_pelotas': comprobantePelotas,
        'created_at': createdAt.toIso8601String(),
      };

  factory Partido.fromMap(Map<String, dynamic> map) => Partido(
        id: map['id'] as int?,
        fecha: DateTime.parse(map['fecha'] as String),
        costoCancha: (map['costo_cancha'] as num?)?.toDouble() ?? 0,
        costoPelotas: (map['costo_pelotas'] as num?)?.toDouble() ?? 0,
        recinto: map['recinto'] as String?,
        notas: map['notas'] as String?,
        comprobanteCancha: map['comprobante_cancha'] as String?,
        comprobantePelotas: map['comprobante_pelotas'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
