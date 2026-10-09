import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/link_contact_dialog.dart';
import 'package:wonderflix/features/account/resend_code_button.dart';

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

  /// Le righe che il testo di [finder] disegna: i riquadri della selezione,
  /// uno per riga (con `maxLines` quelle oltre il tetto non si disegnano).
  int drawnLines(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final boxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
    return boxes.map((box) => box.top).toSet().length;
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
    expect(
        find.text('Ti abbiamo mandato un codice su Discord'), findsOneWidget);
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
    // Un errore lungo va a capo sotto il campo, non si tronca con "…" su una
    // riga. Nei test il font è Ahem (largo il doppio di Inter): questo testo
    // non starebbe in tre righe, quindi qui si conta che vada a capo, e
    // sotto, con "Il bot…", che il testo si veda per intero.
    expect(drawnLines(tester, find.textContaining('Non ti trovo')),
        greaterThan(1));

    api.startLinkFailure = AccountFailure.wrongPassword;
    await submit(tester);
    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(find.textContaining('Non ti trovo'), findsNothing);

    api.startLinkFailure = AccountFailure.dmClosed;
    await submit(tester);
    expect(find.textContaining('Il bot non riesce a scriverti'),
        findsOneWidget);
    expect(
        tester
            .renderObject<RenderParagraph>(
                find.textContaining('Il bot non riesce a scriverti'))
            .didExceedMaxLines,
        isFalse);

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

  /// Il primo passo è fatto: il codice è partito e si è al secondo.
  Future<void> reachCodeStep(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('link-target')), 'garg');
    await tester.enterText(find.byKey(const Key('link-password')), 'segreta');
    await submit(tester);
    expect(find.byKey(const Key('link-code')), findsOneWidget);
  }

  VoidCallback? resendAction(WidgetTester tester) =>
      tester.widget<TextButton>(find.byKey(const Key('resend-code'))).onPressed;

  testWidgets('Rimanda dopo un 429: avviso e il conto riparte',
      (tester) async {
    await open(tester, AccountChannel.discord);
    await reachCodeStep(tester);
    await tester.pump(ResendCodeButton.delay);

    // Ogni rinvio costa un controllo della password: dopo un 429 si aspetta.
    api.startLinkFailure = AccountFailure.rateLimited;
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();

    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
  });

  testWidgets('Rimanda dopo un invio fallito: avviso e subito attivo',
      (tester) async {
    await open(tester, AccountChannel.discord);
    await reachCodeStep(tester);
    await tester.pump(ResendCodeButton.delay);

    api.startLinkFailure = AccountFailure.sendFailed;
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();

    expect(find.text('Invio non riuscito, riprova più tardi'),
        findsOneWidget);
    expect(find.text('Rimanda il codice'), findsOneWidget);
    expect(resendAction(tester), isNotNull);
  });

  testWidgets('Rimanda con la password cambiata altrove: primo passo',
      (tester) async {
    await open(tester, AccountChannel.discord);
    await reachCodeStep(tester);
    await tester.pump(ResendCodeButton.delay);

    api.startLinkFailure = AccountFailure.wrongPassword;
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();

    // L'errore sta sotto il campo della password, che nel secondo passo non
    // c'è: si torna al primo, con il nome già scritto.
    expect(find.byKey(const Key('link-code')), findsNothing);
    expect(find.byKey(const Key('link-password')), findsOneWidget);
    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('link-target')))
            .controller!
            .text,
        'garg');
  });

  testWidgets('Rimanda è spento mentre la conferma è in volo',
      (tester) async {
    await open(tester, AccountChannel.discord);
    await reachCodeStep(tester);
    await tester.pump(ResendCodeButton.delay);
    expect(resendAction(tester), isNotNull);

    api.gate = Completer<void>();
    await tester.enterText(find.byKey(const Key('link-code')), '123456');
    await submit(tester);
    expect(resendAction(tester), isNull);

    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('con la richiesta in volo, Esc e Annulla non chiudono',
      (tester) async {
    api.confirmResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, discordName: 'garg');
    await open(tester, AccountChannel.discord);
    await reachCodeStep(tester);
    await tester.enterText(find.byKey(const Key('link-code')), '123456');
    api.gate = Completer<void>();
    await submit(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('link-code')), findsOneWidget);
    expect(closed, isFalse);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Annulla'))
            .onPressed,
        isNull);

    // La conferma arriva: la finestra si chiude con i contatti.
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(linked!.discordName, 'garg');
  });

  testWidgets('Annulla chiude senza contatti', (tester) async {
    await open(tester, AccountChannel.email);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(linked, isNull);
  });
}
