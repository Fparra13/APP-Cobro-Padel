import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/constants/conceptos_cobro.dart';
import 'package:matchpay/constants/expense_icon.dart';
import 'package:matchpay/domain/gasto_preset_logic.dart';
import 'package:matchpay/models/shared_expense_entry.dart';

void main() {
  SharedExpenseEntry gasto({
    required String label,
    String monto = '0',
    ExpenseIconKey icon = ExpenseIconKey.general,
    String? comprobante,
  }) {
    return SharedExpenseEntry(
      id: 't_${label}_$monto',
      label: label,
      monto: monto,
      iconKey: icon,
      comprobantePath: comprobante,
    );
  }

  test('detecta presets canónicos', () {
    expect(GastoPresetLogic.isVenuePreset('Cancha'), isTrue);
    expect(GastoPresetLogic.isEquipmentPreset('Pelotas'), isTrue);
    expect(GastoPresetLogic.isFixedPreset('Asado'), isFalse);
    expect(GastoPresetLogic.isVenuePreset('cancha'), isFalse);
  });

  test('monto y comprobante desde lista compartida', () {
    final gastos = [
      gasto(label: 'Asado', monto: '10000'),
      gasto(
        label: ConceptosCobro.cancha,
        monto: '40000',
        icon: ExpenseIconKey.court,
        comprobante: 'cancha.jpg',
      ),
      gasto(label: ConceptosCobro.pelotas, monto: '5000'),
    ];

    expect(GastoPresetLogic.montoPreset(gastos, ConceptosCobro.cancha), 40000);
    expect(
      GastoPresetLogic.comprobantePreset(gastos, ConceptosCobro.cancha),
      'cancha.jpg',
    );
    expect(GastoPresetLogic.montoPreset(gastos, ConceptosCobro.pelotas), 5000);
    expect(
      GastoPresetLogic.comprobantePreset(gastos, ConceptosCobro.pelotas),
      isNull,
    );
  });

  test('sharedForVariables excluye presets fijos', () {
    final gastos = [
      gasto(label: ConceptosCobro.cancha, monto: '40000'),
      gasto(label: 'Asado', monto: '12000'),
      gasto(label: '', monto: '100'),
      gasto(label: 'Agua', monto: '0'),
    ];

    final vars = GastoPresetLogic.sharedForVariables(gastos);
    expect(vars, hasLength(1));
    expect(vars.single.label, 'Asado');
  });

  test('iconForPreset', () {
    expect(
      GastoPresetLogic.iconForPreset(ConceptosCobro.cancha),
      ExpenseIconKey.court,
    );
    expect(
      GastoPresetLogic.iconForPreset(ConceptosCobro.pelotas),
      ExpenseIconKey.ball,
    );
  });
}
