import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/datos_pago_organizador.dart';

void main() {
  test('migra legacy banco/cuenta/rut a un solo detalle', () {
    expect(
      DatosPagoOrganizador.detalleDesdeLegacy(
        banco: 'Banco Estado',
        cuenta: '123',
        rut: '1-9',
      ),
      'Banco Estado · 123 · 1-9',
    );
  });

  test('mensaje incluye cómo pagarme sin vacíos', () {
    const pago = DatosPagoOrganizador(
      titular: 'Fran',
      detalle: 'PIX fran@mail.com',
      nota: 'Sube el comprobante',
    );
    final lines = pago.toMessageLines();
    expect(lines.join('\n'), contains('Cómo pagarme'));
    expect(lines.join('\n'), contains('A nombre de: Fran'));
    expect(lines.join('\n'), contains('PIX fran@mail.com'));
    expect(lines.join('\n'), contains('Sube el comprobante'));
  });

  test('sin datos no agrega bloque', () {
    expect(const DatosPagoOrganizador().toMessageLines(), isEmpty);
  });
}
