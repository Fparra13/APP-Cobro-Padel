import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchpay/core/app_settings_controller.dart';
import 'package:matchpay/core/offline_status_controller.dart';
import 'package:matchpay/l10n/matchpay_strings.dart';
import 'package:matchpay/models/detalle_partido.dart';
import 'package:matchpay/utils/cobro_jugador_ui.dart';
import 'package:matchpay/widgets/cobro_ver_detalle_sheet.dart';
import 'package:matchpay/widgets/player_matches_to_close.dart';
import 'package:provider/provider.dart';

class _TestSettings extends AppSettingsController {
  @override
  Locale get locale => const Locale('es');
}

DetallePartido _detalle({
  int partidoId = 10,
  DateTime? fecha,
  String? recinto = 'Starpadel',
}) {
  return DetallePartido(
    partidoId: partidoId,
    jugadorSupabaseId: 'j1',
    asistio: true,
    total: 12000,
    montoPagado: 0,
    pagado: false,
    fechaPartido: fecha ?? DateTime(2026, 7, 10, 20),
    recintoPartido: recinto,
  );
}

/// Reproduce el anti-patrón que rompía Ver detalle: [watch] en un getter
/// evaluado desde onPressed.
class _WatchInCallbackHarness extends StatefulWidget {
  const _WatchInCallbackHarness({required this.useWatchInCallback});

  final bool useWatchInCallback;

  @override
  State<_WatchInCallbackHarness> createState() =>
      _WatchInCallbackHarnessState();
}

class _WatchInCallbackHarnessState extends State<_WatchInCallbackHarness> {
  bool get _readOnlyWatch =>
      context.watch<OfflineStatusController>().isReadOnly;
  bool get _readOnlyRead =>
      context.read<OfflineStatusController>().isReadOnly;

  void _abrirDetalle() {
    final bloqueado =
        widget.useWatchInCallback ? _readOnlyWatch : _readOnlyRead;
    CobroVerDetalleSheet.show(
      context,
      detalle: _detalle(),
      saldoAcumuladoJugador: 12000,
      esAnclaCuenta: true,
      historialSaldo: const [],
      onPayTotal: bloqueado ? null : () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Suscripción legítima en build.
    context.watch<OfflineStatusController>();
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: _abrirDetalle,
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<void> _pumpTeaser(
  WidgetTester tester, {
  required VoidCallback onVerDetalle,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<AppSettingsController>.value(
      value: _TestSettings(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PlayerHomeCobrosTeaser(
              total: 12000,
              pagando: false,
              comprobanteEnRevision: false,
              partidoLinea: 'vie 10 jul · Starpadel',
              onPayTotal: () {},
              onPayOther: () {},
              onVerDetalle: onVerDetalle,
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
    await initializeDateFormatting('es');
  });

  test('detalleCobroParaVerDetalle no queda null si hay deudas', () {
    final deudas = [
      _detalle(
        partidoId: 55,
        fecha: DateTime(2026, 7, 12),
        recinto: 'Club Norte',
      ),
    ];
    final elegido = detalleCobroParaVerDetalle(
      deudas: deudas,
      desgloses: const {},
      saldosAnterioresPorPartido: const {55: 0},
      saldoAcumuladoJugador: 12000,
    );
    expect(elegido, isNotNull);
    expect(elegido!.partidoId, 55);
  });

  test('detalleCobroParaVerDetalle cae al primer cobro si ancla se oculta', () {
    final deudas = [
      _detalle(partidoId: 77, fecha: DateTime(2026, 7, 5)),
    ];
    final elegido = detalleCobroParaVerDetalle(
      deudas: deudas,
      desgloses: const {},
    );
    expect(elegido, isNotNull);
    expect(elegido!.partidoId, 77);
  });

  test('detalleCobroParaVerDetalle con deudas vacías es null', () {
    final elegido = detalleCobroParaVerDetalle(
      deudas: const [],
      desgloses: const {},
      saldoAcumuladoJugador: 5000,
    );
    expect(elegido, isNull);
  });

  test(
    'detalleCobroParaVerDetalle usa saldo de UNA cuenta (no home neto)',
    () {
      // Demo 01: home sería 7000, pero pago/detalle de Org B usa crédito −3000.
      final deudasOrgB = [
        _detalle(partidoId: 99, fecha: DateTime(2026, 7, 1)),
      ];
      final elegido = detalleCobroParaVerDetalle(
        deudas: deudasOrgB,
        desgloses: const {},
        saldosAnterioresPorPartido: const {99: -3000},
        saldoAcumuladoJugador: -3000,
      );
      // Con crédito en esa cuenta no reabre cobro fantasma.
      expect(elegido, isNull);
    },
  );

  testWidgets('Ver detalle del teaser dispara el callback', (tester) async {
    var tapped = false;
    await _pumpTeaser(tester, onVerDetalle: () => tapped = true);

    final l10n = MatchPayStrings.of(const Locale('es'));
    final detailLabel = l10n.tr('cobrosViewDetail');
    expect(find.text(detailLabel), findsOneWidget);

    await tester.ensureVisible(find.text(detailLabel));
    await tester.tap(find.text(detailLabel));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('CobroVerDetalleSheet.show abre contenido visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsController>.value(
        value: _TestSettings(),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      CobroVerDetalleSheet.show(
                        context,
                        detalle: _detalle(),
                        saldoAcumuladoJugador: 12000,
                        esAnclaCuenta: true,
                        historialSaldo: const [],
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = MatchPayStrings.of(const Locale('es'));
    expect(find.text(l10n.tr('cobrosViewChargeTitle')), findsOneWidget);
    expect(find.textContaining('Starpadel'), findsWidgets);
  });

  testWidgets(
    'watch de OfflineStatus en callback de Ver detalle lanza ProviderError',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => OfflineStatusController()),
            ChangeNotifierProvider<AppSettingsController>.value(
              value: _TestSettings(),
            ),
          ],
          child: const MaterialApp(
            home: _WatchInCallbackHarness(useWatchInCallback: true),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isNotNull);
      expect(
        exception.toString(),
        contains('outside of the widget tree'),
      );
    },
  );

  testWidgets(
    'read de OfflineStatus en callback abre el sheet sin error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => OfflineStatusController()),
            ChangeNotifierProvider<AppSettingsController>.value(
              value: _TestSettings(),
            ),
          ],
          child: const MaterialApp(
            home: _WatchInCallbackHarness(useWatchInCallback: false),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final l10n = MatchPayStrings.of(const Locale('es'));
      expect(find.text(l10n.tr('cobrosViewChargeTitle')), findsOneWidget);
    },
  );
}
