import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/core/sport_type.dart';
import 'package:matchpay/models/convocatoria_jugador.dart';
import 'package:matchpay/models/estado_partido.dart';
import 'package:matchpay/models/jugador.dart';
import 'package:matchpay/models/partido.dart';
import 'package:matchpay/widgets/at_risk_convocatoria_actions.dart';
import 'package:matchpay/widgets/organizer_cycle_hero.dart';
import 'package:provider/provider.dart';

class _TestSettings extends AppSettingsController {
  _TestSettings(this.testLocale);

  final Locale testLocale;

  @override
  Locale get locale => testLocale;
}

ConvocatoriaCompleta _convocatoriaSinResolver({int partidoId = 42}) {
  final now = DateTime.now();
  final partido = Partido(
    id: partidoId,
    fecha: now.subtract(const Duration(hours: 3)),
    recinto: 'Las Vizcachas',
    estado: EstadoPartido.organizando,
    cuposMax: 20,
    sportType: SportType.tennis,
    createdAt: now.subtract(const Duration(days: 1)),
  );
  final jugador = Jugador(
    id: 1,
    supabaseId: 'j1',
    nombre: 'Ana',
    createdAt: now,
  );
  return ConvocatoriaCompleta(
    partido: partido,
    jugadores: [
      ConvocatoriaJugadorEntry(
        partidoId: partidoId,
        jugador: jugador,
        estado: EstadoConfirmacion.confirmado,
      ),
    ],
  );
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<AppSettingsController>.value(
    value: _TestSettings(const Locale('es')),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  group('AtRiskConvocatoriaActions', () {
    testWidgets('tap Reprogramar ejecuta override tras el frame', (tester) async {
      var calledId = 0;

      await tester.pumpWidget(
        _wrap(
          AtRiskConvocatoriaActions(
            partidoId: 7,
            reprogramarOverride: (id) async => calledId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reprogramar'));
      await tester.pump(); // post-frame
      await tester.pump();

      expect(calledId, 7);
    });

    testWidgets('tap Cancelar encuentro ejecuta override tras el frame',
        (tester) async {
      var calledId = 0;

      await tester.pumpWidget(
        _wrap(
          AtRiskConvocatoriaActions(
            partidoId: 7,
            cancelarOverride: (id) async => calledId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar encuentro'));
      await tester.pump();
      await tester.pump();

      expect(calledId, 7);
    });
  });

  group('OrganizerCycleHero needsResolution', () {
    testWidgets('muestra los 3 botones de resolución', (tester) async {
      final conv = _convocatoriaSinResolver();
      await tester.pumpWidget(
        _wrap(
          OrganizerCycleHero(
            snapshot: OrganizerCycleSnapshot(
              phase: OrganizerCyclePhase.needsResolution,
              convocatoria: conv,
            ),
            onPrimaryAction: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RESOLVER ENCUENTRO'), findsOneWidget);
      expect(find.text('Marcar como realizado'), findsOneWidget);
      expect(find.text('Reprogramar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('Reprogramar dispara override con partidoId', (tester) async {
      var calledId = 0;
      final conv = _convocatoriaSinResolver(partidoId: 99);

      await tester.pumpWidget(
        _wrap(
          OrganizerCycleHero(
            snapshot: OrganizerCycleSnapshot(
              phase: OrganizerCyclePhase.needsResolution,
              convocatoria: conv,
            ),
            onPrimaryAction: () {},
            rescheduleOverride: (id) async => calledId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Reprogramar'));
      await tester.tap(find.text('Reprogramar'));
      await tester.pump();
      await tester.pump();

      expect(calledId, 99);
    });

    testWidgets('Cancelar dispara override con partidoId', (tester) async {
      var calledId = 0;
      final conv = _convocatoriaSinResolver(partidoId: 55);

      await tester.pumpWidget(
        _wrap(
          OrganizerCycleHero(
            snapshot: OrganizerCycleSnapshot(
              phase: OrganizerCyclePhase.needsResolution,
              convocatoria: conv,
            ),
            onPrimaryAction: () {},
            cancelOverride: (id) async => calledId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump();

      expect(calledId, 55);
    });

    testWidgets('Marcar como realizado dispara callback', (tester) async {
      var marked = false;
      final conv = _convocatoriaSinResolver();

      await tester.pumpWidget(
        _wrap(
          OrganizerCycleHero(
            snapshot: OrganizerCycleSnapshot(
              phase: OrganizerCyclePhase.needsResolution,
              convocatoria: conv,
            ),
            onPrimaryAction: () {},
            onMarkPlayed: () => marked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marcar como realizado'));
      await tester.pump();

      expect(marked, isTrue);
    });

    testWidgets('sin partidoId no muestra Reprogramar/Cancelar', (tester) async {
      final now = DateTime.now();
      final conv = ConvocatoriaCompleta(
        partido: Partido(
          id: null,
          fecha: now.subtract(const Duration(hours: 2)),
          estado: EstadoPartido.organizando,
          cuposMax: 4,
          sportType: SportType.padel,
          createdAt: now,
        ),
        jugadores: const [],
      );

      await tester.pumpWidget(
        _wrap(
          OrganizerCycleHero(
            snapshot: OrganizerCycleSnapshot(
              phase: OrganizerCyclePhase.needsResolution,
              convocatoria: conv,
            ),
            onPrimaryAction: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marcar como realizado'), findsOneWidget);
      expect(find.text('Reprogramar'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
    });
  });
}
