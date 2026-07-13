/// Instrucciones informales de pago del organizador (transferencia fuera de la app).
class DatosPagoOrganizador {
  final String titular;
  final String detalle;
  final String nota;

  const DatosPagoOrganizador({
    this.titular = '',
    this.detalle = '',
    this.nota = '',
  });

  String get titularTrim => titular.trim();
  String get detalleTrim => detalle.trim();
  String get notaTrim => nota.trim();

  /// Hay algo útil para mostrar al jugador.
  bool get tieneDatos =>
      titularTrim.isNotEmpty || detalleTrim.isNotEmpty;

  /// Compone el detalle a partir de campos legacy (banco / cuenta / RUT).
  static String detalleDesdeLegacy({
    String banco = '',
    String cuenta = '',
    String rut = '',
  }) {
    final parts = <String>[
      if (banco.trim().isNotEmpty) banco.trim(),
      if (cuenta.trim().isNotEmpty) cuenta.trim(),
      if (rut.trim().isNotEmpty) rut.trim(),
    ];
    return parts.join(' · ');
  }

  /// Líneas para WhatsApp / detalle de push (no para PDF).
  List<String> toMessageLines({String title = 'Cómo pagarme'}) {
    if (!tieneDatos) return const [];
    final lineas = <String>[
      '',
      '*$title:*',
    ];
    if (titularTrim.isNotEmpty) {
      lineas.add('A nombre de: $titularTrim');
    }
    if (detalleTrim.isNotEmpty) {
      lineas.add(detalleTrim);
    }
    if (notaTrim.isNotEmpty) {
      lineas.add(notaTrim);
    }
    return lineas;
  }
}
