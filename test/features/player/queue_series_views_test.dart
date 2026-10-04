import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  final dark = testItem(
      id: 's1', name: 'Dark', kind: ItemKind.series, childCount: 3);
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
    expect(find.text('3 stagioni'), findsOneWidget);
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
}
