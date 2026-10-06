import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/restart_dialog.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;
  bool? result;

  setUp(() {
    api = FakeAdminApi();
    result = null;
  });

  Future<void> openDialog(WidgetTester tester,
      {Size surfaceSize = const Size(1440, 900)}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showRestartDialog(context),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: adminTestOverrides(api),
      surfaceSize: surfaceSize,
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  testWidgets('chi sta guardando, con titolo', (tester) async {
    api.sessionsValue = testSessions();
    await openDialog(tester);

    expect(find.text('Riavviare Jellyfin?'), findsOneWidget);
    expect(find.text('2 persone stanno guardando:'), findsOneWidget);
    expect(find.text('viviroby — Lost · S1:E3 · Pilota'), findsOneWidget);
    expect(find.text('lucia — Dune (2021)'), findsOneWidget);
    expect(find.text('Il riavvio interrompe la visione e i watch party.'),
        findsOneWidget);
    expect(find.textContaining('davide.sidoti'), findsNothing,
        reason: 'è collegato ma non guarda');
    expect(api.count('sessions'), 1);
  });

  testWidgets('una persona: singolare', (tester) async {
    api.sessionsValue = [testSession('a', 'anna', playing: testMovie)];
    await openDialog(tester);

    expect(find.text('1 persona sta guardando:'), findsOneWidget);
  });

  testWidgets('nessuno', (tester) async {
    api.sessionsValue = [testSession('a', 'anna')];
    await openDialog(tester);

    expect(find.text('Nessuno sta guardando.'), findsOneWidget);
    expect(find.textContaining('interrompe'), findsNothing);
  });

  testWidgets('sessioni illeggibili', (tester) async {
    api.sessionsError = const ServerUnreachableException();
    await openDialog(tester);

    expect(find.text('Non so chi sta guardando.'), findsOneWidget);
  });

  testWidgets('tanti spettatori: la lista scorre e i pulsanti restano',
      (tester) async {
    // Il minimo della finestra dell'app: 1024x640.
    api.sessionsValue = [
      for (var i = 0; i < 20; i++)
        testSession('s$i', 'utente$i', playing: testMovie),
    ];
    await openDialog(tester, surfaceSize: const Size(1024, 640));

    // Un overflow farebbe fallire il test da solo.
    expect(find.text('20 persone stanno guardando:'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    final buttonRect = tester.getRect(find.widgetWithText(FilledButton, 'Riavvia'));
    expect(buttonRect.bottom, lessThanOrEqualTo(640));

    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Annulla: no; Riavvia: sì', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
