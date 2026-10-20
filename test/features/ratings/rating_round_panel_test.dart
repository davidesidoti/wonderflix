import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/features/ratings/rating_round_controller.dart';
import 'package:wonderflix/features/ratings/rating_round_panel.dart';
import 'package:wonderflix/features/ratings/rating_widgets.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/rating_fakes.dart';

/// Parte da una vista data e registra le azioni.
class _Fake extends RatingRoundController {
  _Fake(this.initial);

  final RatingRoundView? initial;
  final calls = <String>[];

  @override
  RatingRoundView? build() => initial;

  @override
  void select(int score) {
    calls.add('select $score');
    state = state?.copyWith(draft: score);
  }

  @override
  Future<void> vote(String? comment) async => calls.add("vote '$comment'");

  @override
  Future<void> skip() async => calls.add('skip');

  @override
  Future<void> reveal() async => calls.add('reveal');

  @override
  void edit() => calls.add('edit');
}

RatingRoundView _view(
  RatingRound round, {
  int? draft,
  bool unavailable = false,
  bool withSource = false,
  RatingSendError? error,
}) =>
    RatingRoundView(
      round: round,
      playlistItemId: 'p1',
      userId: 'u1',
      source: withSource ? testItem(name: 'Il Padrino') : null,
      draft: draft,
      unavailable: unavailable,
      error: error,
    );

Future<_Fake> _pump(WidgetTester tester, RatingRoundView view) async {
  // Un nuovo ProviderScope: gli override non cambiano a scope montato.
  await tester.pumpWidget(const SizedBox());
  final fake = _Fake(view);
  await pumpApp(
    tester,
    Align(
      alignment: Alignment.centerRight,
      child: SizedBox(width: 360, child: RatingRoundPanel(onClose: () {})),
    ),
    overrides: [ratingRoundProvider.overrideWith(() => fake)],
  );
  return fake;
}

Finder _button(Type type, String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(type));

List<Map<String, dynamic>> _voters(
        [String u1 = 'Waiting', String u2 = 'Waiting', String? u3]) =>
    [
      {'UserId': 'u1', 'Name': 'Mario', 'Status': u1},
      {'UserId': 'u2', 'Name': 'Luigi', 'Status': u2},
      if (u3 != null) {'UserId': 'u3', 'Name': 'Peach', 'Status': u3},
    ];

void main() {
  testWidgets("Voting: numeri, commento, Vota spento finché non c'è un numero",
      (tester) async {
    final fake =
        await _pump(tester, _view(testRatingRound(), withSource: true));
    expect(find.text('Il tuo voto · Il Padrino'), findsOneWidget);
    expect(tester.widget<FilledButton>(_button(FilledButton, 'Vota')).onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('rating-score-8')));
    await tester.pump();
    expect(fake.calls, ['select 8']);
    await tester.tap(_button(FilledButton, 'Vota'));
    await tester.tap(_button(OutlinedButton, 'Salta'));
    expect(fake.calls, ['select 8', "vote ''", 'skip']);
  });

  testWidgets('presenti con la spunta e ha saltato, mai i voti degli altri',
      (tester) async {
    await _pump(tester,
        _view(testRatingRound(voters: _voters('Voted', 'Skipped', 'Waiting'))));
    expect(find.text('Hanno votato 1 su 3'), findsOneWidget);
    expect(find.byKey(const Key('rating-voter-done-u1')), findsOneWidget);
    expect(find.byKey(const Key('rating-voter-done-u2')), findsNothing);
    expect(find.text('ha saltato'), findsOneWidget);
    // I soli numeri sono i pulsanti del voto.
    final digits = find.byWidgetPredicate((w) =>
        w is Text &&
        w.data != null &&
        RegExp(r'^\d+$').hasMatch(w.data!) &&
        find
            .ancestor(
                of: find.byWidget(w), matching: find.byType(RatingScorePicker))
            .evaluate()
            .isEmpty);
    expect(digits, findsNothing);
  });

  testWidgets('tempo che resta', (tester) async {
    final endsAt = clock.now().add(const Duration(seconds: 83)).toUtc();
    await _pump(
        tester, _view(testRatingRound(endsAt: endsAt.toIso8601String())));
    expect(find.text('Ancora 1:23'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ancora 1:22'), findsOneWidget);
    await tester.pump(const Duration(seconds: 100));
    expect(find.text('Ancora 0:00'), findsOneWidget);
  });

  testWidgets('Scopri i voti solo con CanReveal', (tester) async {
    await _pump(tester, _view(testRatingRound()));
    expect(find.text('Scopri i voti'), findsNothing);
    final fake = await _pump(tester, _view(testRatingRound(canReveal: true)));
    await tester.tap(find.text('Scopri i voti'));
    expect(fake.calls, ['reveal']);
  });

  testWidgets('dopo il voto: Hai votato 8 e Cambia', (tester) async {
    final fake = await _pump(tester,
        _view(testRatingRound(voters: _voters('Voted'), mine: {'Score': 8})));
    expect(find.text('Hai votato 8'), findsOneWidget);
    expect(find.byKey(const Key('rating-score-8')), findsNothing);
    await tester.tap(find.text('Cambia'));
    expect(fake.calls, ['edit']);
    await _pump(tester, _view(testRatingRound(voters: _voters('Skipped'))));
    expect(find.text('Hai saltato'), findsOneWidget);
    expect(find.text('Cambia'), findsOneWidget);
  });

  testWidgets('errore del voto', (tester) async {
    await _pump(
        tester, _view(testRatingRound(), error: RatingSendError.tooMany));
    expect(find.text('Troppi voti: riprova più tardi'), findsOneWidget);
    await _pump(
        tester, _view(testRatingRound(), error: RatingSendError.notSaved));
    expect(find.text('Voto non salvato'), findsOneWidget);
  });

  RatingRound revealed() => testRatingRound(
        phase: 'Revealed',
        average: 7.5,
        voters: _voters('Voted', 'Voted'),
        results: [
          {'UserId': 'u2', 'Name': 'Luigi', 'Score': 9, 'Comment': 'Capolavoro'},
          {'UserId': 'u1', 'Name': 'Mario', 'Score': 6},
        ],
      );

  testWidgets('Revealed: media del party e risultati', (tester) async {
    await _pump(tester, _view(revealed()));
    expect(find.text('7,5'), findsOneWidget);
    expect(find.text('media del party · 2 voti'), findsOneWidget);
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('Tu'), findsOneWidget);
    expect(find.text('Mario'), findsNothing);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Capolavoro'), findsOneWidget);
    expect(find.text('Puoi cambiare il tuo voto dalla scheda del film'),
        findsOneWidget);
    expect(find.byKey(const Key('rating-score-1')), findsNothing);
  });

  testWidgets('Revealed con le animazioni ridotte: tutte le righe subito',
      (tester) async {
    await _pump(tester, _view(revealed()));
    await tester.pump();
    for (final name in ['Luigi', 'Tu']) {
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text(name), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 1);
    }
  });

  testWidgets('non disponibile', (tester) async {
    await _pump(tester, _view(testRatingRound(), unavailable: true));
    expect(find.text('Votazione non disponibile: puoi votare dalla scheda'),
        findsOneWidget);
  });

  testWidgets('commento iniziale da Mine', (tester) async {
    await _pump(
        tester,
        _view(testRatingRound(mine: {'Score': 8, 'Comment': 'Ottimo'}),
            draft: 8));
    expect(find.text('Ottimo'), findsOneWidget);
  });

  testWidgets('pillola', (tester) async {
    var taps = 0;
    await pumpApp(
        tester,
        Center(
            child: RatingRoundPill(
                phase: RatingPhase.voting, onTap: () => taps++)));
    expect(find.text('Voti del party'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rating-pill')));
    expect(taps, 1);
    await pumpApp(
        tester,
        const Center(
            child: RatingRoundPill(phase: RatingPhase.revealed, onTap: _noop)));
    expect(find.text('Voti scoperti'), findsOneWidget);
  });
}

void _noop() {}
