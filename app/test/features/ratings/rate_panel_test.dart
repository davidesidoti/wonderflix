import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/ratings/friend_ratings_row.dart';
import 'package:wonderflix/features/ratings/rate_panel.dart';
import 'package:wonderflix/features/ratings/rating_widgets.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/tv_field_frame.dart';

void main() {
  late FakeSocialApi api;
  const on = SocialFeatures(friends: true, ratings: true);

  setUp(() => api = FakeSocialApi()..install(features: const {}));

  Future<ProviderContainer> pump(WidgetTester tester,
      {MyRating? mine, bool tv = false, Size? size}) async {
    await pumpApp(
      tester,
      tv: tv,
      surfaceSize: size ?? const Size(1440, 900),
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 360,
            child: Consumer(builder: (context, ref, _) {
              ref.watch(itemRatingsProvider('m1'));
              return RatePanel(
                  subject: RateSubject(
                      item: testItem(id: 'm1', name: 'Dune'),
                      title: 'Dune',
                      mine: mine));
            }),
          ),
        ),
      ),
      overrides: socialTestOverrides(api, features: on),
    );
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RatePanel)));
    // Il pannello si chiude davvero solo se risulta aperto.
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.rate);
    await tester.pump();
    await tester.pump();
    return container;
  }

  Finder button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  Color? fill(WidgetTester tester, int n) =>
      tester.widget<Material>(find.byKey(Key('rating-score-$n'))).color;

  testWidgets('locandina, titolo, numeri e commento dal mio voto',
      (tester) async {
    await pump(tester, mine: const MyRating(score: 8, comment: 'Bello'));
    expect(find.text('Dune'), findsOneWidget);
    expect(fill(tester, 8), isNot(fill(tester, 7)));
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Bello');
    expect(find.text('Togli il mio voto'), findsOneWidget);
  });

  testWidgets('Salva spento senza numero; Salva manda e chiude',
      (tester) async {
    final container = await pump(tester);
    expect(tester.widget<ButtonStyleButton>(button('Salva')).onPressed, isNull);
    await tester.tap(find.byKey(const Key('rating-score-7')));
    await tester.pump();
    await tester.tap(button('Salva'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('rate m1 7 -'));
    expect(container.read(shellPanelProvider), ShellPanel.none);
    await tester.pump();
    expect(api.calls.where((c) => c == 'ratings m1'), hasLength(2));
  });

  testWidgets('Togli il mio voto solo con Mine', (tester) async {
    await pump(tester);
    expect(find.text('Togli il mio voto'), findsNothing);
  });

  testWidgets('Togli il mio voto: unrate e chiude', (tester) async {
    final container = await pump(tester, mine: const MyRating(score: 5));
    await tester.tap(button('Togli il mio voto'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('unrate m1'));
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('errore: il pannello resta con il motivo', (tester) async {
    final container = await pump(tester, mine: const MyRating(score: 6));
    api.nextFailure = SocialFailure.network;
    await tester.tap(button('Salva'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Voto non salvato'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.rate);

    api.nextFailure = SocialFailure.rateLimited;
    await tester.tap(button('Salva'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Troppi voti: riprova più tardi'), findsOneWidget);
    expect(find.text('Voto non salvato'), findsNothing);
    expect(container.read(shellPanelProvider), ShellPanel.rate);
  });

  testWidgets('Salva spento durante il salvataggio', (tester) async {
    await pump(tester, mine: const MyRating(score: 6));
    api.ratingGate = Completer<void>();
    await tester.tap(button('Salva'));
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(button('Salva')).onPressed, isNull);
    expect(
        tester.widget<ButtonStyleButton>(button('Togli il mio voto')).onPressed,
        isNull);
    await tester.tap(button('Salva'), warnIfMissed: false);
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('rate ')), hasLength(1));
    api.ratingGate!.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('in TV il fuoco parte dalla riga dei voti, non dal commento',
      (tester) async {
    await pump(tester, tv: true, size: const Size(960, 540));
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    expect(
        find.descendant(
            of: find.byType(RatingScorePicker),
            matching: find.byElementPredicate((e) => e == focus!.context)),
        findsOneWidget);
  });

  testWidgets('TV: Giù passa sopra il commento senza aprire la tastiera',
      (tester) async {
    await pump(tester, tv: true, size: const Size(960, 540));
    await tester.pump();
    final comment = find.byType(TextField);
    expect(tvFieldFocused(tester, comment), isFalse);
    // Con un voto scelto "Salva" è acceso.
    await tester.tap(find.byKey(const Key('rating-score-10')));
    await tester.pump();
    Focus.of(tester.element(find.byKey(const Key('rating-score-10'))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tvFrameNode(tester, comment).hasPrimaryFocus, isTrue);
    expect(tvFieldFocused(tester, comment), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusOnButton(), isTrue);
    expect(tvFieldFocused(tester, comment), isFalse);
  });
}
