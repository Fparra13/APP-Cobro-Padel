import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/core/sport_type.dart';
import 'package:matchpay/widgets/lazy_indexed_stack.dart';
import 'package:matchpay/widgets/matchpay_preferences_panel.dart';
import 'package:matchpay/widgets/sport_chip_picker.dart';
import 'package:provider/provider.dart';

class _TestSettings extends AppSettingsController {
  _TestSettings({
    this.testLocale = const Locale('es'),
    this.testSport = SportType.padel,
    this.testCurrency = 'CLP',
    this.testCountry = 'CL',
  });

  final Locale testLocale;
  final SportType testSport;
  final String testCurrency;
  final String testCountry;

  @override
  Locale get locale => testLocale;

  @override
  SportType get sport => testSport;

  @override
  String get currencyCode => testCurrency;

  @override
  String get countryCode => testCountry;

  @override
  Future<void> setSport(SportType sport) async {}

  @override
  Future<void> setLocale(Locale locale) async {}

  @override
  Future<void> setCurrency(String code) async {}

  @override
  Future<void> setCountry(String code) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SportChipPicker construye sin overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsController>.value(
        value: _TestSettings(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SportChipPicker(
                value: SportType.padel,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ChoiceChip), findsWidgets);
  });

  testWidgets('MatchPayPreferencesPanel organizador no queda en blanco', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsController>.value(
        value: _TestSettings(),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: MatchPayPreferencesPanel(showSport: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Preferencias'), findsOneWidget);
    expect(find.text('País'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<Locale>), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
  });

  testWidgets('preferences con moneda inválida no crashea', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsController>.value(
        value: _TestSettings(testCurrency: 'XYZ'),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatchPayPreferencesPanel(showSport: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('LazyIndexedStack con índice fuera de rango no queda vacío', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LazyIndexedStack(
            index: 9,
            itemBuilders: [
              () => const Text('tab-0'),
              () => const Text('tab-1'),
              () => const Text('config'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('config'), findsOneWidget);
    expect(find.text('tab-0'), findsNothing);
  });
}
