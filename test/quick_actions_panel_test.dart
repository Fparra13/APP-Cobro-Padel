import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/partido.dart';
import 'package:matchpay/repositories/partido_repository.dart';
import 'package:matchpay/widgets/quick_actions_panel.dart';
import 'package:provider/provider.dart';

class _TestSettings extends AppSettingsController {
  _TestSettings(this.testLocale);

  final Locale testLocale;

  @override
  Locale get locale => testLocale;
}

PartidoCompleto _ultimoPartido({String? recinto}) {
  return PartidoCompleto(
    partido: Partido(
      id: 1,
      fecha: DateTime(2026, 7, 9, 19),
      recinto: recinto ?? 'Starpadel',
      createdAt: DateTime(2026, 1, 1),
      estado: EstadoPartido.jugado,
    ),
    detalles: const [],
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required String languageCode,
  PartidoCompleto? ultimo,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<AppSettingsController>.value(
      value: _TestSettings(Locale(languageCode)),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: QuickActionsPanel(
                resumenes: const [],
                onRefresh: () {},
                ultimoPartido: ultimo,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final lang in ['es', 'en', 'pt']) {
      await initializeDateFormatting(lang);
    }
  });

  for (final lang in ['es', 'en', 'pt']) {
    testWidgets('acciones rapidas sin overflow ($lang)', (tester) async {
      await _pumpPanel(
        tester,
        languageCode: lang,
        ultimo: _ultimoPartido(
          recinto: 'Centro Deportivo Municipal Región Metropolitana',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(QuickActionsPanel), findsOneWidget);
    });
  }
}
