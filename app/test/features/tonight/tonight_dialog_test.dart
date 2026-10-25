import 'package:flutter/material.dart';
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
import 'package:wonderflix/features/tonight/tonight_logic.dart';

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
      ..filtersByKind[ItemKind.movie] =
          const LibraryFilters(genres: ['Azione', 'Dramma'])
      ..filtersByKind[ItemKind.series] =
          const LibraryFilters(genres: ['Anime', 'Dramma']);
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
      overview: 'Paul Atreides arriva su Arrakis.');
  final alien = testItem(id: 'm2', name: 'Alien', runtimeMinutes: 117);

  Future<void> openDialog(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced,
      Size surfaceSize = const Size(1440, 900)}) async {
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
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
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
            body: Center(child: TonightButton(onPressed: () => pressed++))));
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

  testWidgets('Un altro: il prossimo, e il dado gira', (tester) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester, motion: MotionLevel.full);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alien'), findsOneWidget);
    final dice =
        tester.widget<AnimatedRotation>(find.byKey(const Key('tonight-dice')));
    expect(dice.turns, 1);
    expect(dice.duration, WfMotion.slow);
  });

  testWidgets('con le animazioni ridotte il dado non gira', (tester) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    final dice =
        tester.widget<AnimatedRotation>(find.byKey(const Key('tonight-dice')));
    expect(dice.duration, Duration.zero);
  });

  testWidgets('la durata è ferma con Serie', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    await tester.tap(find.text('Serie'));
    await tester.pump();
    await tester.pump();
    final duration = tester.widget<SegmentedButton<TonightDuration>>(
        find.byKey(const Key('tonight-duration')));
    expect(duration.onSelectionChanged, isNull);
    expect(library.randomCalls.last.kinds, {ItemKind.series});
    expect(prefs.getString(tonightTypeKey), 'series');
  });

  testWidgets('con Entrambi i generi dei film e delle serie', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    final picker = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>));
    expect([for (final item in picker.items!) (item.child as Text).data],
        ['Tutti i generi', 'Anime', 'Azione', 'Dramma']);
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

  testWidgets('un genere salvato che non c\'è più torna a tutti i generi',
      (tester) async {
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
        name: 'Il titolo molto lungo di un film che va su due righe, '
            'con il sottotitolo che ne aggiunge altre',
        genres: ['Fantascienza', 'Avventura', 'Dramma'],
        rating: 7.5,
        overview: List.filled(12, 'Una trama molto lunga che occupa righe.')
            .join(' '));
    library.randomPages.add(pageOf([long]));
    await openDialog(tester, surfaceSize: minWindowSize);
    expect(tester.takeException(), isNull);
    // I pulsanti restano in vista: è il titolo che scorre.
    expect(
        tester.getBottomLeft(find.byKey(const Key('tonight-play'))).dy,
        lessThanOrEqualTo(minWindowSize.height));
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
    testWidgets('telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow', (tester) async {
      await openDialog(tester, surfaceSize: size);
      expect(tester.takeException(), isNull);
    });
  }
}
