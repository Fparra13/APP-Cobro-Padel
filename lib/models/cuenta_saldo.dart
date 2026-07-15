/// Cuenta de saldo de un jugador CON un organizador concreto.
///
/// SSOT: `organizador_jugadores.saldo_acumulado`.
/// >0 debe a ese org; <0 crédito solo con ese org.
class CuentaSaldo {
  final String organizadorId;
  final String nombreOrganizador;
  final String? fotoUrl;
  final double saldoAcumulado;
  final bool activo;
  final DateTime? leftAt;

  const CuentaSaldo({
    required this.organizadorId,
    required this.nombreOrganizador,
    this.fotoUrl,
    required this.saldoAcumulado,
    this.activo = true,
    this.leftAt,
  });

  double get deuda =>
      saldoAcumulado > 0.005 ? saldoAcumulado : 0;

  double get credito =>
      saldoAcumulado < -0.005 ? -saldoAcumulado : 0;

  factory CuentaSaldo.fromJson(Map<String, dynamic> json) {
    DateTime? left;
    final rawLeft = json['left_at'];
    if (rawLeft is String) left = DateTime.tryParse(rawLeft);
    return CuentaSaldo(
      organizadorId: '${json['organizador_id'] ?? ''}',
      nombreOrganizador:
          (json['nombre'] as String?)?.trim().isNotEmpty == true
              ? (json['nombre'] as String).trim()
              : 'Organizador',
      fotoUrl: json['foto_url'] as String?,
      saldoAcumulado: (json['saldo_acumulado'] as num?)?.toDouble() ??
          (json['deuda'] as num?)?.toDouble() ??
          0,
      activo: json['activo'] != false,
      leftAt: left,
    );
  }
}
