import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/server_strip.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  Future<void> pumpStrip(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: Padding(padding: EdgeInsets.all(16), child: ServerStrip())),
      overrides: adminTestOverrides(api, session: session),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nome e versione; il sistema solo se Jellyfin lo dice',
      (tester) async {
    await pumpStrip(tester);

    expect(find.text('WonderFlix'), findsOneWidget);
    expect(find.text('Jellyfin 10.11.9'), findsOneWidget);
    expect(find.byKey(const Key('pending-restart')), findsNothing);
    expect(find.text('Riavvia'), findsOneWidget);
  });

  testWidgets('rilegge l\'utente all\'apertura e a ogni lettura del server',
      (tester) async {
    await pumpStrip(tester);
    expect(session.refreshUserCalls, 1);

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(session.refreshUserCalls, 2);
  });

  testWidgets('con il sistema e il riavvio necessario', (tester) async {
    api.serverInfoValue = const ServerInfo(
      name: 'WonderFlix',
      version: '10.11.9',
      operatingSystem: 'Linux',
      hasPendingRestart: true,
    );
    await pumpStrip(tester);

    expect(find.text('Jellyfin 10.11.9 · Linux'), findsOneWidget);
    expect(find.byKey(const Key('pending-restart')), findsOneWidget);
    expect(find.textContaining('Riavvio necessario'), findsOneWidget);
  });

  testWidgets('informazioni illeggibili: errore e Riprova', (tester) async {
    api.serverInfoError = const ServerUnreachableException();
    await pumpStrip(tester);

    expect(find.text('Riprova'), findsOneWidget);

    api.serverInfoError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('WonderFlix'), findsOneWidget);
  });

  testWidgets('Riavvia: conferma, attesa e "Jellyfin è tornato"',
      (tester) async {
    api.upAnswers.addAll([false, true]);
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.calls, contains('restart'));
    expect(find.text('Riavvio in corso…'), findsOneWidget);

    // 3 s: giù; 6 s: di nuovo su.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Jellyfin è tornato'), findsOneWidget);
    expect(find.text('Riavvio in corso…'), findsNothing);
    expect(api.count('info'), greaterThanOrEqualTo(2),
        reason: 'la striscia si rilegge al ritorno');
  });

  testWidgets('Annulla nella conferma: nessun riavvio', (tester) async {
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(api.calls, isNot(contains('restart')));
  });

  testWidgets('3 minuti senza risposta: "non risponde ancora" e Ricontrolla',
      (tester) async {
    api.upAnswers.addAll(List.filled(60, false));
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 180));
    await tester.pump();

    expect(find.text('Jellyfin non risponde ancora'), findsOneWidget);
    expect(find.text('Ricontrolla'), findsOneWidget);

    await tester.tap(find.text('Ricontrolla'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Jellyfin è tornato'), findsOneWidget);
  });

  testWidgets('riavvio rifiutato: "Riavvio non riuscito"', (tester) async {
    api.restartError = const ServerErrorException(500);
    await pumpStrip(tester);

    await tester.tap(find.text('Riavvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Riavvia'));
    await tester.pumpAndSettle();

    expect(find.text('Riavvio non riuscito'), findsOneWidget);
    expect(find.text('Riavvia'), findsOneWidget);
  });
}
