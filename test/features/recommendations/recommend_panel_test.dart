import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/recommendations/recommend_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() {
    api = FakeSocialApi()..install(features: const {});
    api.recommendationTargetsById['m1'] = [
      testTarget('u3', 'Peach'),
      testTarget('u2', 'Luigi', online: true),
      testTarget('u4', 'Toad', canSee: false),
    ];
  });

  Future<void> pump(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 360,
            child: RecommendPanel(subject: RecommendSubject(itemId: 'm1', name: 'Dune')),
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

  // `WfButton.primary` è un `FilledButton.icon`, una sottoclasse: si cerca
  // il pulsante che contiene il testo.
  Finder sendButton() => find.ancestor(
      of: find.text('Invia'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  testWidgets('amici online prima, poi per nome; chi non può vederlo è spento',
      (tester) async {
    await pump(tester);
    expect(api.calls, contains('targets m1'));
    expect(find.text('Dune'), findsOneWidget);
    final luigi = tester.getTopLeft(target('u2')).dy;
    final peach = tester.getTopLeft(target('u3')).dy;
    final toad = tester.getTopLeft(target('u4')).dy;
    expect(luigi < peach && peach < toad, isTrue);
    expect(find.text('Non può vederlo'), findsOneWidget);
    await tester.tap(target('u4'));
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(sendButton()).onPressed, isNull);
  });

  testWidgets('il messaggio non supera 200 caratteri (punti di codice)',
      (tester) async {
    await pump(tester);
    String current() =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    await tester.enterText(find.byType(TextField), 'a' * 201);
    expect(current(), 'a' * 200);
    await tester.enterText(find.byType(TextField), '\u{1F1EE}\u{1F1F9}' * 101);
    expect(current().runes.length, lessThanOrEqualTo(recommendMessageMax));
  });

  testWidgets('nessun amico: lo dice', (tester) async {
    api.recommendationTargetsById['m1'] = [];
    await pump(tester);
    expect(find.text('Nessun amico a cui consigliarlo'), findsOneWidget);
  });

  testWidgets('invio con messaggio: il pannello si chiude e lo dice', (tester) async {
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.tap(target('u3'));
    await tester.enterText(find.byType(TextField), '  da vedere  ');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(api.calls.last, 'recommend m1 u2,u3 da vedere');
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

  testWidgets('al massimo 30 amici alla volta', (tester) async {
    api.recommendationTargetsById['m1'] = [
      for (var i = 0; i < 31; i++) testTarget('u$i', 'Amico ${i.toString().padLeft(2, '0')}'),
    ];
    await pump(tester);
    for (var i = 0; i < 30; i++) {
      await tester.ensureVisible(target('u$i'));
      await tester.tap(target('u$i'));
      await tester.pump();
    }
    await tester.ensureVisible(target('u30'));
    await tester.tap(target('u30'));
    await tester.pump();
    final checkbox = tester.widget<CheckboxListTile>(target('u30'));
    expect(checkbox.value, isFalse);
    // L'avviso è in cima all'elenco, scorso via dalle selezioni.
    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pump();
    expect(find.text('Al massimo 30 amici alla volta'), findsOneWidget);
  });
}
