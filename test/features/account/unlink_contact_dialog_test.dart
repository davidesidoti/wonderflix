import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/unlink_contact_dialog.dart';

import '../../support/account_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAccountApi api;
  bool? unlinked;

  setUp(() {
    api = FakeAccountApi();
    unlinked = null;
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => unlinked =
                await showUnlinkContactDialog(context, AccountChannel.email),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: accountTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String password) async {
    await tester.enterText(find.byKey(const Key('unlink-password')), password);
    await tester.tap(find.byKey(const Key('unlink-submit')));
    await tester.pump();
  }

  testWidgets('password sbagliata resta aperta; giusta scollega',
      (tester) async {
    await open(tester);
    expect(find.text('Scollegare Email?'), findsOneWidget);

    api.unlinkFailure = AccountFailure.wrongPassword;
    await submit(tester, 'x');
    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(unlinked, isNull);

    api.unlinkFailure = null;
    await submit(tester, 'segreta');
    await tester.pumpAndSettle();
    expect(api.unlinkCalls.last, (AccountChannel.email, 'segreta'));
    expect(unlinked, isTrue);
  });

  testWidgets('troppi controlli: avviso sopra il campo', (tester) async {
    api.unlinkFailure = AccountFailure.rateLimited;
    await open(tester);
    await submit(tester, 'segreta');
    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
  });

  testWidgets('con la richiesta in volo, Esc e Annulla non chiudono',
      (tester) async {
    api.gate = Completer<void>();
    await open(tester);
    await submit(tester, 'segreta');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unlink-submit')), findsOneWidget);
    expect(unlinked, isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Annulla'))
            .onPressed,
        isNull);

    // Lo scollegamento riesce: la finestra si chiude con `true`, e la riga
    // si può rileggere.
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(unlinked, isTrue);
  });

  testWidgets('Annulla: false', (tester) async {
    await open(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(unlinked, isFalse);
    expect(api.unlinkCalls, isEmpty);
  });
}
