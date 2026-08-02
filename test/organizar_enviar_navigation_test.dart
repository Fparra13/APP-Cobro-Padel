import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/utils/app_navigation.dart';

/// Stub que reproduce las salidas de navegación de [_enviarConvocatoria]:
/// validación fallida / error antes de persistencia crítica → no pop;
/// éxito completo o éxito parcial (avisos fallaron) → [Navigator.pop] `true`.
class _StubOrganizarSendScreen extends StatelessWidget {
  const _StubOrganizarSendScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizar encuentro')),
      body: Column(
        children: [
          FilledButton(
            key: const Key('send-success'),
            onPressed: () {
              // Misma salida que el final exitoso de _enviarConvocatoria.
              Navigator.of(context).pop(true);
            },
            child: const Text('Enviar invitación'),
          ),
          FilledButton(
            key: const Key('send-partial-notices'),
            onPressed: () {
              // Persistencia crítica OK; avisos fallaron → igual se cierra.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Invitación enviada. Algunos avisos pueden no haberse entregado.',
                  ),
                ),
              );
              Navigator.of(context).pop(true);
            },
            child: const Text('Éxito parcial avisos'),
          ),
          FilledButton(
            key: const Key('send-validation-fail'),
            onPressed: () {
              // Validación: permanece en la ruta (sin pop).
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Faltan participantes')),
              );
            },
            child: const Text('Validación falla'),
          ),
          FilledButton(
            key: const Key('send-error'),
            onPressed: () {
              // Error antes de persistencia crítica: permanece en la ruta.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error de envío')),
              );
            },
            child: const Text('Envío falla'),
          ),
        ],
      ),
    );
  }
}

class _HomeStub extends StatelessWidget {
  const _HomeStub({required this.onOpenOrganizar});

  final VoidCallback onOpenOrganizar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('home-stub'),
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: FilledButton(
          key: const Key('open-organizar'),
          onPressed: onOpenOrganizar,
          child: const Text('Organizar'),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<bool?> openViaContract(
    BuildContext context, {
    required Widget page,
  }) {
    // partidoId != null evita FeatureGate; debugPageBuilder evita repos reales.
    return abrirOrganizarPartido(
      context,
      partidoId: 1,
      debugPageBuilder: (_) => page,
    );
  }

  testWidgets(
    'envío exitoso cierra OrganizarPartidoScreen con resultado true',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return _HomeStub(
                onOpenOrganizar: () async {
                  result = await openViaContract(
                    context,
                    page: const _StubOrganizarSendScreen(),
                  );
                },
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-organizar')));
      await tester.pumpAndSettle();
      expect(find.text('Organizar encuentro'), findsOneWidget);

      await tester.tap(find.byKey(const Key('send-success')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Organizar encuentro'), findsNothing);
      expect(find.byKey(const Key('home-stub')), findsOneWidget);
    },
  );

  testWidgets(
    'éxito parcial (avisos fallaron): cierra con true y no permite reintento',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return _HomeStub(
                onOpenOrganizar: () async {
                  result = await openViaContract(
                    context,
                    page: const _StubOrganizarSendScreen(),
                  );
                },
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-organizar')));
      await tester.pumpAndSettle();
      expect(find.text('Organizar encuentro'), findsOneWidget);

      await tester.tap(find.byKey(const Key('send-partial-notices')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Organizar encuentro'), findsNothing);
      expect(find.byKey(const Key('home-stub')), findsOneWidget);
    },
  );

  testWidgets('error de envío: la ruta permanece abierta', (tester) async {
    bool? result;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return _HomeStub(
              onOpenOrganizar: () async {
                result = await openViaContract(
                  context,
                  page: const _StubOrganizarSendScreen(),
                );
                completed = true;
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-organizar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-error')));
    await tester.pumpAndSettle();

    expect(completed, isFalse);
    expect(result, isNull);
    expect(find.text('Organizar encuentro'), findsOneWidget);
    expect(find.text('Error de envío'), findsOneWidget);
  });

  testWidgets('error de validación: la ruta permanece abierta', (tester) async {
    bool? result;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return _HomeStub(
              onOpenOrganizar: () async {
                result = await openViaContract(
                  context,
                  page: const _StubOrganizarSendScreen(),
                );
                completed = true;
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-organizar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-validation-fail')));
    await tester.pumpAndSettle();

    expect(completed, isFalse);
    expect(result, isNull);
    expect(find.text('Organizar encuentro'), findsOneWidget);
    expect(find.text('Faltan participantes'), findsOneWidget);
  });

  testWidgets(
    'no se crea una segunda instancia del Home al volver',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return _HomeStub(
                onOpenOrganizar: () async {
                  await openViaContract(
                    context,
                    page: const _StubOrganizarSendScreen(),
                  );
                },
              );
            },
          ),
        ),
      );

      expect(find.byKey(const Key('home-stub')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-organizar')));
      await tester.pumpAndSettle();
      // Home permanece en el stack (offstage); no se empuja otro Home.
      expect(
        find.byKey(const Key('home-stub'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Organizar encuentro'), findsOneWidget);

      await tester.tap(find.byKey(const Key('send-success')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-stub')), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Organizar encuentro'), findsNothing);
    },
  );

  testWidgets(
    'abrirOrganizarPartido mantiene contrato Future<bool?> vía push/pop',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    result = await abrirOrganizarPartido(
                      context,
                      partidoId: 42,
                      debugPageBuilder: (ctx) => Scaffold(
                        appBar: AppBar(title: const Text('Organizar encuentro')),
                        body: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('pop-true'),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Organizar encuentro'), findsOneWidget);

      await tester.tap(find.text('pop-true'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );

  test('_enviarConvocatoria cierra con pop(true) tras éxito', () {
    final src = File('lib/screens/organizar_partido_screen.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _enviarConvocatoria()');
    final end = src.indexOf('Future<void> _mostrarWhatsAppSinAppSheet()');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = src.substring(start, end);
    expect(body.contains('Navigator.of(context).pop(true)'), isTrue);
    expect(body.contains('ConvocatoriaSendSemantics.run'), isTrue);
    expect(body.contains('sentWithNotificationGaps') ||
            body.contains('isConsideredSent'), isTrue);
    // Fallos: early return / catch sin pop previo al éxito.
    expect(
      RegExp(r'if \(_titulares\.isEmpty\) \{[^}]+Navigator\.pop').hasMatch(body),
      isFalse,
    );
  });
}
