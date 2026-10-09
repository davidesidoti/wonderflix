import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/link_contact_dialog.dart';

import '../../support/account_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAccountApi api;
  AccountContacts? linked;
  var closed = false;

  setUp(() {
    api = FakeAccountApi();
    linked = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester, AccountChannel channel) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              linked = await showLinkContactDialog(context, channel);
              closed = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: accountTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('link-submit')));
    await tester.pump();
  }

  testWidgets('Discord: nome e password, poi il codice e i contatti nuovi',
      (tester) async {
    api.confirmResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, discordName: 'garg');
    await open(tester, AccountChannel.discord);
    expect(find.text('Collega Discord'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('link-target')), '  garg ');
    await tester.enterText(find.byKey(const Key('link-password')), 'segreta');
    await submit(tester);

    expect(api.startLinkCalls.single, (
      channel: AccountChannel.discord,
      target: 'garg',
      password: 'segreta',
      language: 'it',
    ));
    expect(find.text('Ti abbiamo mandato un codice su Discord'), findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
    expect(find.byKey(const Key('link-password')), findsNothing);

    await tester.enterText(find.byKey(const Key('link-code')), ' 012345 ');
    await submit(tester);
    await tester.pumpAndSettle();

    expect(api.confirmCalls.single, (AccountChannel.discord, '012345'));
    expect(closed, isTrue);
    expect(linked!.discordName, 'garg');
  });

  testWidgets('primo passo: gli errori sotto il campo giusto o sopra',
      (tester) async {
    await open(tester, AccountChannel.discord);

    // Nome vuoto: nessuna chiamata.
    await submit(tester);
    expect(find.text('Nome utente Discord non valido'), findsOneWidget);
    expect(api.startLinkCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('link-target')), 'garg');
    api.startLinkFailure = AccountFailure.memberNotFound;
    await submit(tester);
    expect(find.textContaining('Non ti trovo nel server Discord'),
        findsOneWidget);

    api.startLinkFailure = AccountFailure.wrongPassword;
    await submit(tester);
    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(find.textContaining('Non ti trovo'), findsNothing);

    api.startLinkFailure = AccountFailure.dmClosed;
    await submit(tester);
    expect(find.textContaining('Il bot non riesce a scriverti'),
        findsOneWidget);

    api.startLinkFailure = AccountFailure.rateLimited;
    await submit(tester);
    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);

    api.startLinkFailure = AccountFailure.channelOff;
    await submit(tester);
    expect(find.text('Non disponibile su questo server'), findsOneWidget);

    expect(find.byKey(const Key('link-code')), findsNothing);
  });

  testWidgets('email: codice sbagliato, Rimanda con la stessa password',
      (tester) async {
    await open(tester, AccountChannel.email);
    await tester.enterText(
        find.byKey(const Key('link-target')), 'a@example.com');
    await tester.enterText(find.byKey(const Key('link-password')), 'segreta');
    await submit(tester);
    expect(find.text('Ti abbiamo mandato un codice a a@example.com'),
        findsOneWidget);

    api.confirmFailure = AccountFailure.invalidCode;
    await tester.enterText(find.byKey(const Key('link-code')), '111111');
    await submit(tester);
    expect(find.text('Codice non valido o scaduto'), findsOneWidget);
    expect(closed, isFalse);

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();

    expect(api.startLinkCalls, hasLength(2));
    expect(api.startLinkCalls.last.target, 'a@example.com');
    expect(api.startLinkCalls.last.password, 'segreta');
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
  });

  testWidgets('mentre il codice parte, un secondo clic non fa niente',
      (tester) async {
    api.gate = Completer<void>();
    await open(tester, AccountChannel.discord);
    await tester.enterText(find.byKey(const Key('link-target')), 'garg');
    await submit(tester);
    await submit(tester);
    expect(api.startLinkCalls, hasLength(1));

    api.gate!.complete();
    await tester.pump();
    expect(find.byKey(const Key('link-code')), findsOneWidget);
  });

  testWidgets('email non valida dal plugin: sotto il campo', (tester) async {
    api.startLinkFailure = AccountFailure.invalidTarget;
    await open(tester, AccountChannel.email);
    await tester.enterText(find.byKey(const Key('link-target')), 'non-email');
    await submit(tester);
    expect(find.text('Email non valida'), findsOneWidget);
  });

  testWidgets('Annulla chiude senza contatti', (tester) async {
    await open(tester, AccountChannel.email);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(linked, isNull);
  });
}
