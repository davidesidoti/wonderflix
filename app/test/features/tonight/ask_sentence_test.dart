import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/tonight/ask_parts.dart';
import 'package:wonderflix/features/tonight/ask_sentence.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';

import '../../support/pump_app.dart';

void main() {
  final changes = <TonightFilters>[];

  setUp(changes.clear);

  Future<void> pump(
    WidgetTester tester,
    TonightFilters filters, {
    AskVoice voice = AskVoice.tonight,
    bool readOnly = false,
    bool tv = false,
    Size surfaceSize = const Size(1280, 800),
    List<String> genres = const ['Azione', 'Dramma'],
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AskSentence(
            filters: filters,
            voice: voice,
            onChanged: readOnly ? null : changes.add,
          ),
        ),
      ),
      tv: tv,
      surfaceSize: surfaceSize,
      overrides: [
        tonightGenresProvider.overrideWith((ref, type) async => genres),
      ],
    );
    await tester.pump();
  }

  const film = TonightFilters(type: TonightType.movies);
  const keys = ['ask-type', 'ask-duration', 'ask-genre', 'ask-rating'];

  testWidgets('la frase e le quattro parole', (tester) async {
    await pump(tester, film);
    expect(find.text('Stasera'), findsOneWidget);
    expect(find.text('un film'), findsOneWidget);
    expect(find.text('di qualsiasi durata'), findsOneWidget);
    for (final key in keys) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('con le serie non c\'è la durata', (tester) async {
    await pump(tester, const TonightFilters(type: TonightType.series));
    expect(find.text('una serie'), findsOneWidget);
    expect(find.byKey(const Key('ask-duration')), findsNothing);
    expect(find.byKey(const Key('ask-type')), findsOneWidget);
    expect(find.byKey(const Key('ask-genre')), findsOneWidget);
    expect(find.byKey(const Key('ask-rating')), findsOneWidget);
  });

  testWidgets('il voto si sceglie dal menu', (tester) async {
    await pump(tester, film);
    await tester.tap(find.byKey(const Key('ask-rating')));
    await tester.pumpAndSettle();
    expect(find.text('Qualsiasi voto'), findsOneWidget);
    expect(find.text('Belli (7 o più)'), findsOneWidget);
    expect(find.text('Brutti (5 o meno)'), findsOneWidget);
    await tester.tap(find.text('Belli (7 o più)'));
    await tester.pumpAndSettle();
    expect(changes, [film.copyWith(rating: TonightRating.good)]);
  });

  testWidgets('il genere: tutti e quelli del server', (tester) async {
    await pump(tester, film.copyWith(genre: 'Dramma'));
    expect(find.text('di genere Dramma'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ask-genre')));
    await tester.pumpAndSettle();
    expect(find.text('Tutti i generi'), findsOneWidget);
    expect(find.text('Azione'), findsOneWidget);
    await tester.tap(find.text('Tutti i generi'));
    await tester.pumpAndSettle();
    expect(changes, [film]);
  });

  testWidgets('un genere che non c\'è più torna a tutti', (tester) async {
    await pump(tester, film.copyWith(genre: 'Western'));
    await tester.pump();
    expect(changes, [film]);
  });

  testWidgets('sola lettura: la frase senza pulsanti', (tester) async {
    await pump(tester, film, readOnly: true);
    expect(find.text('un film'), findsOneWidget);
    for (final key in keys) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(find.byType(PopupMenuButton<Object>), findsNothing);
  });

  testWidgets('TV: focus tra le parole, OK apre, Back chiude', (tester) async {
    await pump(tester, film, tv: true);
    // Il focus del pulsante della parola (quello dell'InkWell).
    FocusNode node(String key) => Focus.of(
      tester.element(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      ),
    );

    node('ask-type').requestFocus();
    await tester.pump();
    expect(node('ask-type').hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(node('ask-duration').hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Meno di 90 minuti'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Meno di 90 minuti'), findsNothing);
    expect(node('ask-duration').hasFocus, isTrue);
    expect(changes, isEmpty);
  });

  testWidgets('a 390 la frase va a capo senza sbordare', (tester) async {
    await pump(
      tester,
      const TonightFilters(
        type: TonightType.both,
        duration: TonightDuration.under120,
        genre: 'Fantascienza e avventura',
        rating: TonightRating.good,
      ),
      voice: AskVoice.match,
      surfaceSize: const Size(390, 780),
      genres: const ['Fantascienza e avventura'],
    );
    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.byKey(const Key('ask-type')));
    final last = tester.getTopLeft(find.byKey(const Key('ask-rating')));
    expect(last.dy, greaterThan(first.dy));
  });
}
