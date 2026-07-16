import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/l10n/matchpay_strings.dart';
import 'package:matchpay/models/comprobante_estado.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/widgets/desglose_cobro_panel.dart';

void main() {
  final l10n = MatchPayStrings('es');

  DetallePartido det({
    double total = 5000,
    double pagado = 0,
    ComprobanteEstado? estado,
  }) {
    return DetallePartido(
      partidoId: 1,
      total: total,
      montoPagado: pagado,
      comprobanteEstado: estado,
    );
  }

  test('encuentro cubierto muestra Pagado aunque haya deuda anterior en snap', () {
    // Snap +5000 de deuda vieja; este partido cargo 5000 y abono 5000.
    final texto = estadoTextoCobro(
      det(total: 5000, pagado: 5000),
      l10n,
      saldoAnteriorAlPartido: 5000,
    );
    expect(texto, l10n.tr('cobroStatusPaid'));
  });

  test('encuentro sin cubrir sigue Pendiente', () {
    final texto = estadoTextoCobro(
      det(total: 5000, pagado: 0),
      l10n,
      saldoAnteriorAlPartido: 0,
    );
    expect(texto, l10n.tr('cobroStatusPending'));
  });
}
