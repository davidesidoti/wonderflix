import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/window_setup.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/features/tonight/tonight_dialog.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late SharedPreferences prefs;
  TonightChoice? choice;
  var closed = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    library = FakeLibraryApi()
      ..filtersByKind[ItemKind.movie] = const LibraryFilters(
        genres: ['Azione', 'Dramma'],
      )
      ..filtersByKind[ItemKind.series] = const LibraryFilters(
        genres: ['Anime', 'Dramma'],
      );
    choice = null;
    closed = false;
  });

  final dune = testItem(
    id: 'm1',
    name: 'Dune',
    year: 2021,
    runtimeMinutes: 155,
    genres: ['Fantascienza'],
    rating: 8.1,
    overview: 'Paul Atreides arriva su Arrakis.',
  );
  final alien = testItem(id: 'm2', name: 'Alien', runtimeMinutes: 117);

  Future<void> openDialog(
    WidgetTester tester, {
    MotionLevel motion = MotionLevel.reduced,
    Size surfaceSize = const Size(1440, 900),
    bool tv = false,
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                choice = await showTonightDialog(context);
                closed = true;
              },
              child: const Text('apri'),
            ),
          ),
        ),
      ),
      motion: motion,
      surfaceSize: surfaceSize,
      tv: tv,
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('il pulsante chiama quello che gli si dà, e non apre da solo '
      'la finestra', (tester) async {
    var pressed = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(child: TonightButton(onPressed: () => pressed++)),
      ),
    );
    expect(find.text('Cosa guardo stasera?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tonight-button')));
    await tester.pump();
    expect(pressed, 1);
    expect(find.byKey(const Key('tonight-play')), findsNothing);
  });

  testWidgets('propone un titolo con i suoi dati', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    expect(find.text('Cosa guardo stasera?'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('2021 · 2h 35m · Fantascienza'), findsOneWidget);
    expect(find.text('8.1'), findsOneWidget);
    expect(find.text('Paul Atreides arriva su Arrakis.'), findsOneWidget);
    expect(find.text('Riproduci'), findsOneWidget);
    expect(find.text('Dettagli'), findsOneWidget);
    expect(find.text('Un altro'), findsOneWidget);
  });

  testWidgets('Un altro: il prossimo, e il dado del pulsante gira', (
    tester,
  ) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester, motion: MotionLevel.full);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alien'), findsOneWidget);
    final dice = tester.widget<AnimatedRotation>(
      find.byKey(const Key('tonight-dice')),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tonight-another')),
        matching: find.byKey(const Key('tonight-dice')),
      ),
      findsOneWidget,
    );
    expect(dice.turns, 1);
    expect(dice.duration, WfMotion.slow);
  });

  testWidgets('con le animazioni ridotte il dado non gira', (tester) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    final dice = tester.widget<AnimatedRotation>(
      find.byKey(const Key('tonight-dice')),
    );
    expect(dice.duration, Duration.zero);
  });

  Future<void> pick(WidgetTester tester, String key, String item) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(item).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> another(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Gli id di "Già proposti", da sinistra a destra.
  List<String> history(WidgetTester tester) {
    const prefix = 'tonight-history-';
    final keys = [
      for (final element
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(prefix),
              )
              .evaluate())
        (element.widget.key! as ValueKey<String>).value,
    ];
    double left(String key) => tester.getTopLeft(find.byKey(Key(key))).dx;
    keys.sort((a, b) => left(a).compareTo(left(b)));
    return [for (final key in keys) key.substring(prefix.length)];
  }

  testWidgets('desktop: la locandina a sinistra, il perché, il nome grande', (
    tester,
  ) async {
    final film = testItem(
      id: 'm1',
      name: 'Dune',
      year: 2021,
      runtimeMinutes: 155,
      genres: ['Science Fiction'],
      rating: 8.1,
      overview: 'Paul Atreides arriva su Arrakis.',
    );
    library.randomPages.add(pageOf([film]));
    await openDialog(tester);
    final poster = find.byKey(const Key('tonight-poster'));
    expect(tester.getSize(poster).width, 172);
    expect(
      tester.getTopRight(poster).dx,
      lessThan(tester.getTopLeft(find.text('Dune')).dx),
    );
    expect(find.text('Un film che non hai mai visto'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Dune')).style?.fontSize, 46);
    expect(find.text('2021 · 2h 35m · Fantascienza'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('ask-type'))).dy,
      lessThan(tester.getTopLeft(poster).dy),
    );
    expect(find.byType(SegmentedButton<Object>), findsNothing);
    expect(tester.getSize(find.byType(TonightDialog)).width, 760);
  });

  testWidgets('una serie: il suo perché', (tester) async {
    await prefs.setString(tonightTypeKey, 'series');
    library.randomPages.add(
      pageOf([
        testItem(
          id: 's1',
          name: 'Dark',
          kind: ItemKind.series,
          recursiveCount: 8,
          unplayedCount: 8,
        ),
      ]),
    );
    await openDialog(tester);
    expect(find.text('Una serie che non hai mai iniziato'), findsOneWidget);
  });

  final five = [
    for (final n in [1, 2, 3, 4, 5]) testItem(id: 'm$n', name: 'Titolo $n'),
  ];

  testWidgets('Già proposti: Un altro ci mette il titolo, al massimo 3', (
    tester,
  ) async {
    library.randomPages.add(pageOf(five));
    await openDialog(tester);
    expect(find.text('Già proposti'), findsNothing);
    await another(tester);
    expect(find.text('Già proposti'), findsOneWidget);
    expect(history(tester), ['m1']);
    await another(tester);
    await another(tester);
    expect(history(tester), ['m1', 'm2', 'm3']);
    await another(tester);
    expect(history(tester), ['m2', 'm3', 'm4']);
    expect(find.text('Titolo 5'), findsOneWidget);
  });

  testWidgets('Già proposti: un clic rimette il titolo, quello di prima in '
      'fondo', (tester) async {
    library.randomPages.add(pageOf(five));
    await openDialog(tester);
    await another(tester);
    await another(tester);
    expect(history(tester), ['m1', 'm2']);
    await tester.tap(find.byKey(const Key('tonight-history-m1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Titolo 1'), findsOneWidget);
    expect(find.text('Titolo 3'), findsNothing);
    expect(history(tester), ['m2', 'm3']);
    // Dopo il clic "Un altro" va avanti con la pescata.
    await another(tester);
    expect(find.text('Titolo 4'), findsOneWidget);
    expect(history(tester), ['m2', 'm3', 'm1']);
  });

  testWidgets('cambiare un filtro svuota Già proposti', (tester) async {
    library.randomPages.add(pageOf(five));
    await openDialog(tester);
    await another(tester);
    expect(history(tester), ['m1']);
    await pick(tester, 'ask-type', 'Serie');
    expect(history(tester), isEmpty);
    expect(find.text('Già proposti'), findsNothing);
  });

  testWidgets('Un altro finito in errore: in Già proposti solo il titolo '
      "che c'era", (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    library.error = const ServerUnreachableException();
    await another(tester);
    expect(find.text('Riprova'), findsOneWidget);
    expect(history(tester), ['m1']);
    library.error = null;
    library.randomPages
      ..clear()
      ..add(pageOf([alien]));
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alien'), findsOneWidget);
    expect(history(tester), ['m1']);
  });

  testWidgets('Un altro senza titoli: in Già proposti solo il titolo che '
      "c'era", (tester) async {
    library.randomPages.addAll([
      pageOf([dune]),
      pageOf([], 0),
    ]);
    await openDialog(tester);
    await another(tester);
    expect(find.text('Nessun titolo con questi filtri'), findsOneWidget);
    expect(history(tester), ['m1']);
  });

  double pickOpacity(WidgetTester tester, String name) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(name), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  testWidgets('il titolo nuovo entra in dissolvenza', (tester) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester, motion: MotionLevel.full);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pickOpacity(tester, 'Alien'), lessThan(1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(pickOpacity(tester, 'Alien'), 1);
  });

  testWidgets('con le animazioni ridotte il titolo è subito in vista', (
    tester,
  ) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    await tester.pump();
    expect(pickOpacity(tester, 'Alien'), 1);
  });

  testWidgets('stretto: locandina a tutta larghezza, pulsanti in due righe', (
    tester,
  ) async {
    final long = testItem(
      id: 'm3',
      name:
          'Il titolo molto lungo di un film che va su due righe, '
          'con il sottotitolo che ne aggiunge altre',
      genres: ['Fantascienza', 'Avventura', 'Dramma'],
      rating: 7.5,
      overview: List.filled(
        12,
        'Una trama molto lunga che occupa righe.',
      ).join(' '),
    );
    library.randomPages.add(pageOf([long]));
    await openDialog(tester, surfaceSize: const Size(390, 780));
    expect(tester.takeException(), isNull);
    final poster = tester.getSize(find.byKey(const Key('tonight-poster')));
    expect(poster.width, 390 - 32);
    expect(poster.height, lessThanOrEqualTo(330));
    final another = find.byKey(const Key('tonight-another'));
    final play = find.byKey(const Key('tonight-play'));
    final details = find.byKey(const Key('tonight-details'));
    await tester.ensureVisible(details);
    await tester.pump();
    expect(tester.getTopLeft(another).dy, tester.getTopLeft(play).dy);
    expect(
      tester.getTopLeft(details).dy,
      greaterThan(tester.getBottomLeft(play).dy),
    );
    expect(tester.getSize(details).width, 390 - 32);
  });

  testWidgets('TV: il focus parte da Un altro, Su va alla frase', (
    tester,
  ) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester, tv: true);
    FocusNode node(Finder of) => Focus.of(
      tester.element(
        find.descendant(of: of, matching: find.byType(Text)).first,
      ),
    );
    expect(node(find.byKey(const Key('tonight-another'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    const words = ['ask-type', 'ask-duration', 'ask-genre', 'ask-rating'];
    expect(words.any((key) => node(find.byKey(Key(key))).hasFocus), isTrue);
    expect(tester.getSize(find.byType(TonightDialog)).width, 680);
  });

  testWidgets("con Serie la durata non c'è", (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    expect(find.byKey(const Key('ask-duration')), findsOneWidget);
    await pick(tester, 'ask-type', 'Serie');
    expect(find.text('una serie'), findsOneWidget);
    expect(find.byKey(const Key('ask-duration')), findsNothing);
    expect(library.randomCalls.last.kinds, {ItemKind.series});
    expect(prefs.getString(tonightTypeKey), 'series');
  });

  testWidgets('con Entrambi i generi dei film e delle serie', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('ask-genre')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      [
        for (final item in tester.widgetList<PopupMenuItem<Object>>(
          find.byType(PopupMenuItem<Object>),
        ))
          (item.child! as Text).data,
      ],
      ['Tutti i generi', 'Anime', 'Azione', 'Dramma'],
    );
  });

  testWidgets('nessun titolo: il messaggio e Togli i filtri', (tester) async {
    await prefs.setString(tonightGenreKey, 'Dramma');
    library.randomPages.add(pageOf([], 0));
    await openDialog(tester);
    expect(find.text('Nessun titolo con questi filtri'), findsOneWidget);
    await tester.tap(find.text('Togli i filtri'));
    await tester.pump();
    await tester.pump();
    expect(library.randomCalls.last.genre, isNull);
    expect(prefs.getString(tonightGenreKey), isNull);
  });

  testWidgets('un genere salvato che non c\'è più torna a tutti i generi', (
    tester,
  ) async {
    await prefs.setString(tonightGenreKey, 'Western');
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    expect(library.randomCalls.last.genre, isNull);
    expect(prefs.getString(tonightGenreKey), isNull);
  });

  testWidgets('errore: il messaggio e Riprova', (tester) async {
    library.error = const ServerUnreachableException();
    await openDialog(tester);
    expect(find.text('Riprova'), findsOneWidget);
    library.error = null;
    library.randomPages.add(pageOf([dune]));
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('nella finestra più piccola non sborda', (tester) async {
    final long = testItem(
      id: 'm3',
      name:
          'Il titolo molto lungo di un film che va su due righe, '
          'con il sottotitolo che ne aggiunge altre',
      genres: ['Fantascienza', 'Avventura', 'Dramma'],
      rating: 7.5,
      overview: List.filled(
        12,
        'Una trama molto lunga che occupa righe.',
      ).join(' '),
    );
    library.randomPages.add(pageOf([long]));
    await openDialog(tester, surfaceSize: minWindowSize);
    expect(tester.takeException(), isNull);
    // I pulsanti restano in vista: è il titolo che scorre.
    expect(
      tester.getBottomLeft(find.byKey(const Key('tonight-play'))).dy,
      lessThanOrEqualTo(minWindowSize.height),
    );
  });

  testWidgets('Dettagli e Riproduci chiudono con la scelta', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('tonight-details')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(closed, isTrue);
    expect(choice, isA<TonightDetails>());
    expect(choice!.item.id, 'm1');

    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('tonight-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(choice, isA<TonightPlay>());
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
      (tester) async {
        await openDialog(tester, surfaceSize: size);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
