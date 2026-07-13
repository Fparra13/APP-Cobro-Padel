import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/widgets/at_risk_convocatoria_actions.dart';
import 'package:provider/provider.dart';

class _TestSettings extends AppSettingsController {
  _TestSettings(this.testLocale);

  final Locale testLocale;

  @override
  Locale get locale => testLocale;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget _wrap(Widget child) {
    return ChangeNotifierProvider<AppSettingsController>.value(
      value: _TestSettings(const Locale('es')),
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('tap reprogramar ejecuta acción tras el frame', (tester) async {
    var reprogramCalled = false;

    await tester.pumpWidget(
      _wrap(
        AtRiskConvocatoriaActions(
          partidoId: 7,
          reprogramarOverride: (id) async {
            reprogramCalled = true;
            expect(id, 7);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reprogramar'));
    await tester.pump();
    await tester.pump();

    expect(reprogramCalled, isTrue);
  });

  testWidgets('tap cancelar ejecuta acción tras el frame', (tester) async {
    var cancelCalled = false;

    await tester.pumpWidget(
      _wrap(
        AtRiskConvocatoriaActions(
          partidoId: 7,
          cancelarOverride: (id) async {
            cancelCalled = true;
            expect(id, 7);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar encuentro'));
    await tester.pump();
    await tester.pump();

    expect(cancelCalled, isTrue);
  });

  testWidgets('rescheduleFilled false usa outlined y sigue disparando',
      (tester) async {
    var called = false;

    await tester.pumpWidget(
      _wrap(
        AtRiskConvocatoriaActions(
          partidoId: 3,
          rescheduleFilled: false,
          rescheduleLabel: 'Reprogramar',
          cancelLabel: 'Cancelar',
          reprogramarOverride: (_) async => called = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reprogramar'));
    await tester.pump();
    await tester.pump();

    expect(called, isTrue);
  });
}
