import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _montoFieldHasFocus(WidgetTester tester) {
  final editable = tester.state<EditableTextState>(
    find.descendant(
      of: find.byKey(const Key('monto')),
      matching: find.byType(EditableText),
    ),
  );
  return editable.widget.focusNode?.hasFocus ?? false;
}

void main() {
  testWidgets(
    'TextField de monto conserva foco si el campo vive en child estable',
    (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: ctrl,
              builder: (context, child) {
                final monto = double.tryParse(
                      ctrl.text.replaceAll(RegExp(r'[^\d]'), ''),
                    ) ??
                    0;
                return Column(
                  children: [
                    child!,
                    if (monto > 0) const Text('extra'),
                  ],
                );
              },
              child: TextField(
                key: const Key('monto'),
                controller: ctrl,
                keyboardType: TextInputType.number,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('monto')));
      await tester.pump();
      expect(_montoFieldHasFocus(tester), isTrue);

      await tester.enterText(find.byKey(const Key('monto')), '5');
      await tester.pump();
      expect(find.text('extra'), findsOneWidget);
      expect(_montoFieldHasFocus(tester), isTrue);

      await tester.enterText(find.byKey(const Key('monto')), '50');
      await tester.pump();
      expect(_montoFieldHasFocus(tester), isTrue);
    },
  );

  testWidgets(
    'recrear TextField con ValueKey variable pierde el foco',
    (tester) async {
      var text = '';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              final monto = double.tryParse(text) ?? 0;
              return Scaffold(
                body: Column(
                  children: [
                    TextField(
                      key: ValueKey('field-$monto'),
                      onChanged: (v) => setState(() => text = v),
                    ),
                    if (monto > 0) const Text('extra'),
                  ],
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '5');
      await tester.pump();

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(editable.widget.focusNode?.hasFocus ?? false, isFalse);
    },
  );
}
