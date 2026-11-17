import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/recommendations/recommend_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/tv_field_frame.dart';

void main() {
  late FakeSocialApi api;

  setUp(() {
    api = FakeSocialApi()..install(features: const {});
    api.recommendationTargetsById['m1'] = [
      testTarget('u1', 'sara', online: true),
      testTarget('u2', 'Garg', online: true),
      testTarget('u3', 'marta', canSee: false),
      testTarget('u4', 'Peach'),
    ];
  });

  Future<void> pump(WidgetTester tester,
      {bool tv = false,
      bool touch = false,
      Size size = const Size(1440, 900),
      double width = 360,
      double textScale = 1}) async {
    await pumpApp(
      tester,
      tv: tv,
      touch: touch,
      surfaceSize: size,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: width,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: const RecommendPanel(
                    subject: RecommendSubject(itemId: 'm1', name: 'Dune')),
              ),
            ),
          ),
        ),
      ),
      overrides: socialTestOverrides(api,
          features: const SocialFeatures(friends: true, recommendations: true)),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder target(String userId) => find.byKey(ValueKey('recommend-target-$userId'));
  Finder check(String userId) => find.byKey(ValueKey('recommend-check-$userId'));
  Finder message() => find.widgetWithText(TextField, 'Messaggio, se vuoi');
  Finder search() => find.widgetWithText(TextField, 'Cerca tra gli amici');
  Finder grid() => find.descendant(
      of: find.byKey(const ValueKey('recommend-scroll')),
      matching: find.byType(Scrollable)).first;

  // `WfButton.primary` è un `FilledButton.icon`, una sottoclasse: si cerca
  // il pulsante del piede, qualunque cosa dica.
  Finder sendButton() => find.ancestor(
      of: find.byIcon(LucideIcons.send),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  testWidgets('amici online prima, poi per nome; chi non può vederlo è spento',
      (tester) async {
    await pump(tester);
    expect(api.calls, contains('targets m1'));
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Consiglia'), findsOneWidget);
    // Griglia: in ordine da sinistra, sulla stessa riga.
    final xs = [
      for (final id in ['u2', 'u1', 'u4', 'u3']) tester.getTopLeft(target(id)).dx
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(find.text('Non può vederlo'), findsOneWidget);
    await tester.tap(target('u3'), warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(sendButton()).onPressed, isNull);
  });

  testWidgets('griglia: toccare accende, il pulsante conta', (tester) async {
    await pump(tester);
    expect(find.text('Invia'), findsOneWidget);
    expect(find.text('Scegli almeno un amico'), findsOneWidget);
    await tester.tap(target('u1'));
    await tester.pump();
    expect(check('u1'), findsOneWidget);
    expect(find.text('Invia a 1 amico'), findsOneWidget);
    expect(find.text('Scegli almeno un amico'), findsNothing);
    expect(find.text('Non può vederlo'), findsOneWidget);
    await tester.tap(target('u3'), warnIfMissed: false);
    await tester.pump();
    expect(check('u3'), findsNothing);
    // Toccato di nuovo si spegne.
    await tester.tap(target('u1'));
    await tester.pump();
    expect(check('u1'), findsNothing);
    expect(find.text('Invia'), findsOneWidget);
  });

  testWidgets('Scegli gli online: al massimo 30, poi il limite', (tester) async {
    api.recommendationTargetsById['m1'] = [
      for (var i = 0; i < 35; i++)
        testTarget('u$i', 'Amico ${i.toString().padLeft(2, '0')}', online: true),
      testTarget('off', 'Zeta'),
    ];
    await pump(tester);
    expect(find.text('Al massimo 30 amici alla volta'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recommend-pick-online')));
    await tester.pump();
    expect(find.text('Invia a 30 amici'), findsOneWidget);
    expect(find.text('Al massimo 30 amici alla volta'), findsOneWidget);
    for (var i = 30; i < 35; i++) {
      await tester.scrollUntilVisible(target('u$i'), 100, scrollable: grid());
      // La casella è spenta: il tocco non la raggiunge, ed è quello che si prova.
      await tester.tap(target('u$i'), warnIfMissed: false);
      await tester.pump();
      expect(check('u$i'), findsNothing);
    }
    expect(find.text('Invia a 30 amici'), findsOneWidget);
    // Uno in meno: il limite sparisce.
    await tester.scrollUntilVisible(target('u0'), -100, scrollable: grid());
    await tester.ensureVisible(target('u0'));
    await tester.pump();
    await tester.tap(target('u0'));
    await tester.pump();
    expect(find.text('Invia a 29 amici'), findsOneWidget);
    expect(find.text('Al massimo 30 amici alla volta'), findsNothing);
  });

  testWidgets('il messaggio non supera 200 caratteri (punti di codice)',
      (tester) async {
    await pump(tester);
    String current() => tester.widget<TextField>(message()).controller!.text;
    await tester.enterText(message(), 'a' * 201);
    expect(current(), 'a' * 200);
    await tester.enterText(message(), '\u{1F1EE}\u{1F1F9}' * 101);
    expect(current().runes.length, lessThanOrEqualTo(recommendMessageMax));
  });

  testWidgets('il contatore compare solo vicino al limite', (tester) async {
    await pump(tester);
    await tester.enterText(message(), 'a' * 179);
    await tester.pump();
    expect(find.text('179/200'), findsNothing);
    await tester.enterText(message(), 'a' * 181);
    await tester.pump();
    expect(find.text('181/200'), findsOneWidget);
  });

  testWidgets('la ricerca filtra la griglia', (tester) async {
    await pump(tester);
    await tester.enterText(search(), 'gar');
    await tester.pump();
    expect(target('u2'), findsOneWidget);
    expect(target('u1'), findsNothing);
    expect(target('u3'), findsNothing);
    expect(target('u4'), findsNothing);
  });

  testWidgets('ricerca senza risultati: una riga che lo dice', (tester) async {
    await pump(tester);
    await tester.enterText(search(), 'zzz');
    await tester.pump();
    expect(find.text('Nessun amico con questo nome'), findsOneWidget);
    expect(target('u1'), findsNothing);
  });

  testWidgets('Scegli gli online con la ricerca: solo i mostrati', (tester) async {
    await pump(tester);
    await tester.enterText(search(), 'gar');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('recommend-pick-online')));
    await tester.pump();
    expect(check('u2'), findsOneWidget);
    expect(find.text('Invia a 1 amico'), findsOneWidget);
  });

  testWidgets('380 di larghezza e testo a 1,5: niente overflow', (tester) async {
    await pump(tester, size: const Size(1440, 900), width: 380, textScale: 1.5);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('recommend-pick-online')), findsOneWidget);
  });

  for (final size in const [Size(800, 360), Size(390, 640)]) {
    testWidgets('altezza corta $size: niente overflow, il piede resta', (tester) async {
      await pump(tester, size: size);
      expect(tester.takeException(), isNull);
      expect(sendButton(), findsOneWidget);
      expect(tester.getBottomRight(sendButton()).dy, lessThanOrEqualTo(size.height));
    });
  }

  testWidgets('caselle alte almeno 44 a 390×780, niente overflow', (tester) async {
    await pump(tester, size: const Size(390, 780));
    expect(tester.getSize(target('u1')).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nessun amico: lo dice', (tester) async {
    api.recommendationTargetsById['m1'] = [];
    await pump(tester);
    expect(find.text('Nessun amico a cui consigliarlo'), findsOneWidget);
  });

  testWidgets('invio con messaggio: il pannello si chiude e lo dice', (tester) async {
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.tap(target('u1'));
    await tester.enterText(message(), '  da vedere  ');
    await tester.pump();
    expect(find.text('Invia a 2 amici'), findsOneWidget);
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(api.calls.last, 'recommend m1 u2,u1 da vedere');
    expect(find.text('Consiglio inviato a 2 amici'), findsOneWidget);
  });

  testWidgets('nessun destinatario valido: non inviato, il pannello resta',
      (tester) async {
    api.recommendSent = 0;
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(find.text('Consiglio non inviato'), findsOneWidget);
    expect(find.byType(RecommendPanel), findsOneWidget);
    expect(api.calls.last, 'recommend m1 u2 -');
  });

  testWidgets('troppi consigli: lo dice', (tester) async {
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.pump();
    api.nextFailure = SocialFailure.rateLimited;
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(find.text('Troppi consigli: riprova più tardi'), findsOneWidget);
  });

  testWidgets('Invia spento durante l\'invio', (tester) async {
    api.recommendGate = Completer<void>();
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(sendButton()).onPressed, isNull);
    api.recommendGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('recommend ')), hasLength(1));
  });

  testWidgets('elenco non caricato: errore e Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pump(tester);
    expect(find.text('Impossibile caricare gli amici'), findsOneWidget);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(target('u2'), findsOneWidget);
  });

  testWidgets('in TV il fuoco parte dal primo amico, non dalla ricerca',
      (tester) async {
    await pump(tester, tv: true, size: const Size(960, 540));
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    expect(
        find.descendant(
            of: target('u2'),
            matching: find.byElementPredicate((e) => e == focus!.context)),
        findsOneWidget,
        reason: 'Garg è il primo amico (online)');
  });

  testWidgets('TV: Giù dalla griglia passa le cornici e arriva a Invia',
      (tester) async {
    await pump(tester, tv: true, size: const Size(960, 540));
    await tester.pump();
    // Con qualcuno scelto "Invia" è acceso.
    await tester.tap(target('u1'));
    await tester.pump();
    Focus.of(tester.element(find.text('sara'))).requestFocus();
    await tester.pump();
    var reached = false;
    for (var i = 0; i < 6 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tvFieldFocused(tester, message()), isFalse);
      expect(tvFieldFocused(tester, search()), isFalse);
      reached = focusOnButton();
    }
    expect(reached, isTrue);
    expect(find.text('Invia a 1 amico'), findsOneWidget);
  });

  bool focusInside(WidgetTester tester, Finder of) {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context != null &&
        find
            .descendant(
                of: of,
                matching: find.byElementPredicate((e) => e == focus!.context))
            .evaluate()
            .isNotEmpty;
  }

  testWidgets('stretto con la tastiera (senza touch): il fuoco parte dal primo amico',
      (tester) async {
    await pump(tester, size: const Size(390, 780));
    await tester.pump();
    expect(focusInside(tester, target('u2')), isTrue);
  });

  testWidgets('stretto col dito: nessun fuoco nel pannello', (tester) async {
    await pump(tester, touch: true, size: const Size(390, 780));
    await tester.pump();
    expect(focusInside(tester, find.byType(RecommendPanel)), isFalse);
  });
}
