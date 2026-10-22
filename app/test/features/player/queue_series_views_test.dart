import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/queue_panel/queue_series_views.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeLibraryApi library;

  // Come nelle risposte vere di ricerca e preferiti: senza `ChildCount`.
  final dark = testItem(id: 's1', name: 'Dark', kind: ItemKind.series);
  final season1 =
      testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.other);
  final season2 =
      testItem(id: 'se2', name: 'Stagione 2', kind: ItemKind.other);
  final season3 =
      testItem(id: 'se3', name: 'Stagione 3', kind: ItemKind.other);

  JellyfinItem episode(String id, String seasonId, int index) => testItem(
      id: id,
      name: 'Episodio $index',
      kind: ItemKind.episode,
      seriesId: 's1',
      seriesName: 'Dark',
      seasonId: seasonId,
      index: index,
      seasonIndex: seasonId == 'se1' ? 1 : 2,
      runtimeMinutes: 52);

  setUp(() {
    library = FakeLibraryApi()
      ..seasonsBySeries['s1'] = [season1, season2, season3]
      // La stagione 3 ha solo episodi mancanti: non arrivano.
      ..seriesEpisodes['s1'] = [
        episode('a1', 'se1', 1),
        episode('a2', 'se1', 2),
        episode('a3', 'se1', 3),
        episode('b1', 'se2', 1),
        episode('b2', 'se2', 2),
      ];
  });

  /// In coda e4 (in corso), a1, a2: due episodi della stagione 1.
  final queue = testSeriesQueue(itemIds: const ['e4', 'a1', 'a2']);

  Future<void> pump(WidgetTester tester, Widget view) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 360, height: 900, child: view)),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        libraryApiProvider.overrideWithValue(library),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('serie: stagioni con gli episodi, già in coda, una richiesta',
      (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: queue,
        onAdd: (items, {required next}) async => calls.add(
            '${next ? 'next' : 'end'} ${items.map((i) => i.id).join(',')}'),
        onOpenSeason: (season) => calls.add('season ${season.id}'),
        onBack: () => calls.add('back'),
        onClose: () => calls.add('close'),
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('2 stagioni'), findsOneWidget,
        reason: 'le stagioni con episodi veri');
    expect(find.text('3 episodi · 2 già in coda'), findsOneWidget);
    expect(find.text('2 episodi'), findsOneWidget);
    expect(find.text('Stagione 3'), findsNothing,
        reason: 'nessun episodio vero');
    expect(library.allEpisodesCalls, ['s1']);

    final row1 = find.byKey(const ValueKey('queue-season-se1'));
    await tester.tap(find.descendant(
        of: row1, matching: find.byTooltip(l.partyQueuePlayNext)));
    await tester.pump();
    final row2 = find.byKey(const ValueKey('queue-season-se2'));
    await tester.tap(find.descendant(
        of: row2, matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    await tester.tap(find.text('Stagione 2'));
    expect(calls, ['next a3', 'end b1,b2', 'season se2'],
        reason: 'la stagione 1 manda solo l\'episodio che manca');
  });

  testWidgets('serie: stagione tutta in coda → ✓', (tester) async {
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: testSeriesQueue(itemIds: const ['e4', 'a1', 'a2', 'a3']),
        onAdd: (items, {required next}) async {},
        onOpenSeason: (_) {},
        onBack: () {},
        onClose: () {},
      ),
    );
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('queue-season-se1')),
            matching: find.text(l.partyQueueInQueue)),
        findsOneWidget);
  });

  testWidgets('stagione: tutta dopo, tutta in coda, episodi singoli',
      (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      QueueSeasonView(
        series: dark,
        season: season1,
        queue: queue,
        onAdd: (items, {required next}) async => calls.add(
            '${next ? 'next' : 'end'} ${items.map((i) => i.id).join(',')}'),
        onBack: () => calls.add('back'),
        onClose: () => calls.add('close'),
      ),
    );
    expect(find.text('Stagione 1'), findsOneWidget);
    expect(find.text('Dark · 3 episodi'), findsOneWidget);
    expect(find.text('1. Episodio 1'), findsOneWidget);
    expect(find.text('52m'), findsNWidgets(3));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('queue-episode-a1')),
            matching: find.text(l.partyQueueInQueue)),
        findsOneWidget);
    await tester.tap(find.text(l.partyQueueWholeSeasonNext));
    await tester.pump();
    await tester.tap(find.text(l.partyQueueWholeSeasonEnd));
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('queue-episode-a3')),
        matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    await tester.tap(find.byTooltip(l.navBack));
    expect(calls, ['next a3', 'end a3', 'end a3', 'back']);
  });

  testWidgets('serie: il sottotitolo arriva con stagioni ed episodi',
      (tester) async {
    library.delay = const Duration(milliseconds: 500);
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 360,
            height: 900,
            child: QueueSeriesView(
              series: dark,
              queue: queue,
              onAdd: (items, {required next}) async {},
              onOpenSeason: (_) {},
              onBack: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        libraryApiProvider.overrideWithValue(library),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    await tester.pump();
    expect(find.text('Dark'), findsOneWidget);
    expect(find.textContaining('stagioni'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('2 stagioni'), findsOneWidget);
  });

  testWidgets('serie: coda piena, i pulsanti spenti non aprono la stagione',
      (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: testSeriesQueue(
            itemIds: [for (var i = 0; i < 100; i++) 'x$i'], playingIndex: 0),
        onAdd: (items, {required next}) async => calls.add('add'),
        onOpenSeason: (season) => calls.add('season ${season.id}'),
        onBack: () {},
        onClose: () {},
      ),
    );
    final row = find.byKey(const ValueKey('queue-season-se2'));
    final buttons = find.descendant(
        of: row, matching: find.byTooltip(l.partyQueueFull(100)));
    expect(buttons, findsNWidgets(2));
    await tester.tap(buttons.first);
    await tester.pump();
    await tester.tap(buttons.last);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('serie: mentre una aggiunta aspetta, i pulsanti non aprono la '
      'stagione', (tester) async {
    final calls = <String>[];
    final gate = Completer<void>();
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: queue,
        onAdd: (items, {required next}) {
          calls.add('add');
          return gate.future;
        },
        onOpenSeason: (season) => calls.add('season ${season.id}'),
        onBack: () {},
        onClose: () {},
      ),
    );
    final row = find.byKey(const ValueKey('queue-season-se2'));
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip(l.partyQueuePlayNext)));
    await tester.pump();
    expect(calls, ['add']);
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip(l.partyQueuePlayNext)));
    await tester.pump();
    expect(calls, ['add'], reason: 'né un altra aggiunta né la stagione');
    gate.complete();
    await tester.pump();
  });

  testWidgets('serie senza episodi veri: niente "0 stagioni", "Nessun '
      'episodio disponibile"', (tester) async {
    // Le stagioni ci sono, ma con soli episodi mancanti.
    library.seriesEpisodes['s1'] = const [];
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: queue,
        onAdd: (items, {required next}) async {},
        onOpenSeason: (_) {},
        onBack: () {},
        onClose: () {},
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    expect(find.textContaining('stagioni'), findsNothing);
    expect(find.text(l.partyQueueSeriesEmpty), findsOneWidget);
    expect(find.text('Stagione 1'), findsNothing);
  });

  testWidgets('serie: errore con Riprova', (tester) async {
    library.error = const ServerUnreachableException();
    await pump(
      tester,
      QueueSeriesView(
        series: dark,
        queue: queue,
        onAdd: (items, {required next}) async {},
        onOpenSeason: (_) {},
        onBack: () {},
        onClose: () {},
      ),
    );
    expect(find.text(l.partyQueueLoadFailed), findsOneWidget);
    expect(find.textContaining('stagioni'), findsNothing);
    library.error = null;
    await tester.tap(find.text(l.retry));
    await tester.pump();
    await tester.pump();
    expect(find.text('3 episodi · 2 già in coda'), findsOneWidget);
    expect(library.allEpisodesCalls, ['s1', 's1']);
  });

  testWidgets('stagione: il sottotitolo con gli episodi solo quando ci sono',
      (tester) async {
    library.error = const ServerUnreachableException();
    await pump(
      tester,
      QueueSeasonView(
        series: dark,
        season: season1,
        queue: queue,
        onAdd: (items, {required next}) async {},
        onBack: () {},
        onClose: () {},
      ),
    );
    expect(find.text(l.partyQueueLoadFailed), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget, reason: 'solo la serie');
    expect(find.textContaining('episodi'), findsNothing);
    library.error = null;
    await tester.tap(find.text(l.retry));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dark · 3 episodi'), findsOneWidget);
    expect(library.allEpisodesCalls, ['s1', 's1']);
  });

  testWidgets('stagione: una aggiunta alla volta, con l attesa in vista',
      (tester) async {
    final calls = <String>[];
    final gate = Completer<void>();
    await pump(
      tester,
      QueueSeasonView(
        series: dark,
        season: season1,
        queue: queue,
        onAdd: (items, {required next}) {
          calls.add('${next ? 'next' : 'end'} ${items.length}');
          return gate.future;
        },
        onBack: () {},
        onClose: () {},
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text(l.partyQueueWholeSeasonNext));
    await tester.pump();
    expect(calls, ['next 1']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text(l.partyQueueWholeSeasonEnd));
    await tester.pump();
    await tester.tap(find.text(l.partyQueueWholeSeasonNext));
    await tester.pump();
    expect(calls, ['next 1'], reason: 'mentre aspetta non si ripreme');
    gate.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text(l.partyQueueWholeSeasonEnd));
    await tester.pump();
    expect(calls, ['next 1', 'end 1']);
  });

  testWidgets('stagione: coda piena, "Tutta dopo" e "Tutta in coda" spenti '
      'con il motivo', (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      QueueSeasonView(
        series: dark,
        season: season1,
        queue: testSeriesQueue(
            itemIds: [for (var i = 0; i < 100; i++) 'x$i'], playingIndex: 0),
        onAdd: (items, {required next}) async => calls.add('add'),
        onBack: () {},
        onClose: () {},
      ),
    );
    for (final label in [
      l.partyQueueWholeSeasonNext,
      l.partyQueueWholeSeasonEnd,
    ]) {
      expect(
          find.ancestor(
              of: find.text(label),
              matching: find.byTooltip(l.partyQueueFull(100))),
          findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(calls, isEmpty);
  });
}
