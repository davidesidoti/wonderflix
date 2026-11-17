import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/config/app_config.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';
import 'package:wonderflix/features/auth/quick_connect_panel.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

class FakeRunner implements QuickConnectRunner {
  final controllers = <StreamController<QcState>>[];

  StreamController<QcState> get current => controllers.last;

  @override
  Stream<QcState> run() {
    controllers.add(StreamController<QcState>());
    return current.stream;
  }
}

void main() {
  test('formatta il codice a gruppi di tre', () {
    expect(formatQuickConnectCode('482913'), '482 913');
    expect(formatQuickConnectCode('12345'), '12345');
  });

  testWidgets('mostra il codice e completa il login quando approvato',
      (tester) async {
    final runner = FakeRunner();
    final session = FakeSessionController(const SessionSignedOut());
    await pumpApp(tester, const QuickConnectPanel(), overrides: [
      quickConnectRunnerProvider.overrideWithValue(runner),
      sessionControllerProvider.overrideWith(() => session),
    ]);

    runner.current.add(const QcWaiting('482913'));
    await tester.pump();
    expect(find.text('482 913'), findsOneWidget);
    expect(find.text('In attesa di approvazione…'), findsOneWidget);

    runner.current.add(const QcApproved(testUser));
    await tester.pump();
    expect(session.approvedUser?.id, 'u1');
  });

  testWidgets('errore: pulsante Riprova riavvia il flusso', (tester) async {
    final runner = FakeRunner();
    await pumpApp(tester, const QuickConnectPanel(), overrides: [
      quickConnectRunnerProvider.overrideWithValue(runner),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedOut())),
    ]);

    runner.current.add(const QcError(ServerUnreachableException()));
    await tester.pump();
    await tester.tap(find.text('Riprova'));
    await tester.pump();

    expect(runner.controllers.length, 2);
  });

  Future<void> pumpWaiting(WidgetTester tester, {bool tv = false}) async {
    final runner = FakeRunner();
    await pumpApp(tester, const QuickConnectPanel(), tv: tv, overrides: [
      quickConnectRunnerProvider.overrideWithValue(runner),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedOut())),
    ]);
    runner.current.add(const QcWaiting('482913'));
    await tester.pump();
  }

  testWidgets('codice grande e tabellare, due passi col nome vero della voce',
      (tester) async {
    await pumpWaiting(tester);

    expect(find.text('Il tuo codice'), findsOneWidget);
    final code = tester.widget<Text>(find.text('482 913'));
    expect(code.style!.fontSize, 68);
    expect(code.style!.letterSpacing, 6);
    expect(code.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()));
    expect(
        find.text(
            'Su un dispositivo già collegato apri Impostazioni › Account › Autorizza un dispositivo.'),
        findsOneWidget);
    expect(find.text('Scrivi il codice e premi Autorizza.'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Non hai un altro dispositivo collegato?'),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, "Scrivi all'admin"), findsOneWidget);
  });

  testWidgets("senza supportUrl niente riga dell'admin", (tester) async {
    final runner = FakeRunner();
    await pumpApp(tester, const QuickConnectPanel(), overrides: [
      quickConnectRunnerProvider.overrideWithValue(runner),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedOut())),
      appConfigProvider.overrideWithValue(AppConfig(
        serverUrl: Uri.parse('https://media.example.com'),
        githubRepo: 'owner/repo',
        discordAppId: '1',
        supportUrl: null,
      )),
    ]);
    runner.current.add(const QcWaiting('482913'));
    await tester.pump();

    expect(find.text('Non hai un altro dispositivo collegato?'), findsNothing);
    expect(find.text("Scrivi all'admin"), findsNothing);
  });

  testWidgets("TV: chiedere all'admin è un testo, non un link", (tester) async {
    await pumpWaiting(tester, tv: true);

    expect(find.text("Chiedi all'admin di autorizzarti"), findsOneWidget);
    expect(find.text("Scrivi all'admin"), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
