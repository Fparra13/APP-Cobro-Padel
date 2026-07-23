import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/l10n/payment_concept_l10n.dart';

void main() {
  test('traduce conceptos actuales de encuentro', () {
    expect(
      PaymentConceptL10n.translate('Encuentro al día', 'en'),
      'Gathering settled',
    );
    expect(
      PaymentConceptL10n.translate(
        'Encuentro cubierto con saldo a favor',
        'en',
      ),
      'Session covered with credit balance',
    );
  });

  test('mapea legacy Partido … a keys actuales', () {
    expect(
      PaymentConceptL10n.translate('Partido pagado', 'es'),
      'Encuentro al día',
    );
    expect(
      PaymentConceptL10n.translate('Partido pagado', 'en'),
      'Gathering settled',
    );
    expect(
      PaymentConceptL10n.translate(
        'Partido cubierto con saldo a favor',
        'pt',
      ),
      'Encontro coberto com saldo a favor',
    );
  });

  test('mapea conceptos legacy de pago/deuda a labels nuevos', () {
    expect(
      PaymentConceptL10n.translate('Encuentro pagado', 'es'),
      'Encuentro al día',
    );
    expect(
      PaymentConceptL10n.translate('Deuda acumulada', 'es'),
      'Pendiente acumulado',
    );
    expect(
      PaymentConceptL10n.translate('Pago parcial', 'en'),
      'Partial contribution',
    );
  });
}
