import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/core/space/space_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/space/space_providers.dart';
import 'package:wonderflix/features/space/space_tab.dart';

import '../../support/admin_fakes.dart';
import '../../support/download_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/space_fakes.dart';

SpaceCandidate _candidate(
  String key, {
  String? title,
  String kind = 'Movie',
  int? season,
  String? seriesKey,
  List<String> via = const [],
  List<String> keep = const [],
  List<String> genres = const [],
}) => SpaceCandidate(
  key: key,
  kind: kind,
  title: title ?? 'Titolo $key',
  seasonNumber: season,
  seriesKey: seriesKey,
  sizeBytes: 2000000000,
  freeNowBytes: 2000000000,
  freeLaterBytes: 0,
  inPackBytes: 0,
  via: via,
  keep: keep,
  viewers: const [],
  requests: const [],
  ratingCount: 0,
  genres: genres,
);

SpaceOverview _overview({
  DateTime? scannedAt,
  bool scanning = false,
  List<SpaceCandidate> delete = const [],
  List<SpaceLighten> lighten = const [],
  SpaceCleanup cleanup = const SpaceCleanup(),
  SpaceErrors errors = const SpaceErrors(),
  List<String> topGenres = const [],
  List<SpaceKept> kept = const [],
  List<SpaceKept> atMinimum = const [],
}) => SpaceOverview(
  scannedAt: scannedAt,
  scanning: scanning,
  quota: const SpaceQuota(usedBytes: 3000000000000, limitBytes: 4000000000000),
  breakdown: SpaceOverview.empty.breakdown,
  delete: delete,
  lighten: lighten,
  cleanup: cleanup,
  pending: const [],
  kept: kept,
  atMinimum: atMinimum,
  operations: const [],
  topGenres: topGenres,
  errors: errors,
);

final _scanned = DateTime.now().subtract(const Duration(hours: 2));

void main() {
  late FakeSpaceApi api;
  late FakeDownloadsApi downloads;

  setUp(() {
    api = FakeSpaceApi();
    downloads = FakeDownloadsApi();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    Size size = const Size(1440, 20000),
  }) async {
    await pumpApp(
      tester,
      const Scaffold(body: SpaceTab()),
      overrides: [
        ...adminTestOverrides(
          FakeAdminApi(),
          downloads: downloads,
          features: const SocialFeatures(
            inbox: true,
            downloads: true,
            space: true,
            known: true,
          ),
        ),
        spaceApiProvider.overrideWithValue(api),
      ],
      surfaceSize: size,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('BeforeTheFirstScanShowsCalculating', (tester) async {
    api.overviewValue = _overview(scanning: true);
    await pumpTab(tester);

    expect(find.text('Calcolo in corso…'), findsOneWidget);
    expect(find.text('Cancellare'), findsNothing);
  });

  testWidgets('AFailedScanShowsRetry', (tester) async {
    api.overviewValue = _overview();
    await pumpTab(tester);

    expect(find.text('Calcolo non riuscito'), findsOneWidget);
    await tester.tap(find.text('Ricalcola'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('recalculate'));
  });

  testWidgets('AggiornaRereadsWithoutRecalculating', (tester) async {
    api.overviewValue = _overview();
    await pumpTab(tester);
    api.calls.clear();

    await tester.tap(find.text('Aggiorna'));
    await tester.pumpAndSettle();

    expect(api.calls, ['overview']);
  });

  testWidgets('SeasonsAreGroupedUnderTheSeries', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      delete: [
        _candidate(
          'season:7:1',
          title: 'Serie Lunga',
          kind: 'Season',
          season: 1,
          seriesKey: 'series:7',
        ),
        _candidate(
          'season:7:2',
          title: 'Serie Lunga',
          kind: 'Season',
          season: 2,
          seriesKey: 'series:7',
        ),
      ],
    );
    await pumpTab(tester);

    expect(find.text('Serie Lunga'), findsOneWidget);
    expect(find.text('4,00 GB'), findsOneWidget);
    expect(find.text('Stagione 1'), findsNothing);
    await tester.tap(find.text('Serie Lunga'));
    await tester.pump();
    expect(find.text('Stagione 1'), findsOneWidget);
    expect(find.text('Stagione 2'), findsOneWidget);
  });

  testWidgets('TwentyRowsThenShowMore', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      delete: [for (var i = 0; i < 25; i++) _candidate('movie:$i')],
    );
    await pumpTab(tester);

    expect(find.textContaining('Titolo movie:'), findsNWidgets(20));
    await tester.tap(find.text('Mostra altri'));
    await tester.pump();
    expect(find.textContaining('Titolo movie:'), findsNWidgets(25));
    expect(find.text('Mostra altri'), findsNothing);
  });

  testWidgets('LightenOpensTheSearchWithLighten', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      lighten: const [
        SpaceLighten(
          key: 'movie:1',
          kind: 'Movie',
          title: 'Film',
          sizeBytes: 9000000000,
          excessBytes: 5000000000,
          gbPerHour: 6.5,
        ),
      ],
    );
    await pumpTab(tester);

    expect(find.text('9,00 GB · 6,5 GB/ora · 5,00 GB in più'), findsOneWidget);
    await tester.tap(find.text('Alleggerisci'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Scarica').first);
    await tester.pumpAndSettle();

    expect(downloads.calls, contains('grab movie:1 g1 3 lighten'));
  });

  group('AtMinimum in Tenuti', () {
    const emptyText = 'Nessun titolo tenuto';

    testWidgets('both lists empty shows the empty text', (tester) async {
      api.overviewValue = _overview(scannedAt: _scanned);
      await pumpTab(tester);

      expect(find.text(emptyText), findsOneWidget);
    });

    testWidgets('shows its label and the removal unmarks it', (tester) async {
      api.overviewValue = _overview(
        scannedAt: _scanned,
        kept: const [SpaceKept(key: 'movie:1', title: 'Tenuto')],
        atMinimum: const [SpaceKept(key: 'movie:1', title: 'Minimo')],
      );
      await pumpTab(tester);

      expect(find.text(emptyText), findsNothing);
      final row = find.byKey(const ValueKey('at-minimum-movie:1'));
      expect(
        find.descendant(of: row, matching: find.text('Già al minimo')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('kept-movie:1')),
          matching: find.text('Già al minimo'),
        ),
        findsNothing,
      );

      await tester.tap(find.descendant(of: row, matching: find.text('Togli')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('unmarkAtMinimum movie:1'));
      expect(api.calls, isNot(contains('unkeep movie:1')));
    });

    testWidgets('only at minimum hides the empty text', (tester) async {
      api.overviewValue = _overview(
        scannedAt: _scanned,
        atMinimum: const [SpaceKept(key: 'movie:1', title: 'Minimo')],
      );
      await pumpTab(tester);

      expect(find.text(emptyText), findsNothing);
    });

    testWidgets('both lists share one page of rows', (tester) async {
      api.overviewValue = _overview(
        scannedAt: _scanned,
        kept: [
          for (var i = 0; i < 15; i++)
            SpaceKept(key: 'movie:$i', title: 'Tenuto $i'),
        ],
        atMinimum: [
          for (var i = 0; i < 10; i++)
            SpaceKept(key: 'movie:$i', title: 'Minimo $i'),
        ],
      );
      await pumpTab(tester);

      expect(find.textContaining('Tenuto '), findsNWidgets(15));
      expect(find.textContaining('Minimo '), findsNWidgets(5));
      await tester.tap(find.text('Mostra altri'));
      await tester.pump();
      expect(find.textContaining('Minimo '), findsNWidgets(10));
    });
  });

  testWidgets('ServiceErrorsAreNotes', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      errors: const SpaceErrors(qbit: 'Unauthorized'),
      delete: [_candidate('movie:1')],
    );
    await pumpTab(tester);

    expect(
      find.text('qBittorrent: utente o password sbagliati'),
      findsOneWidget,
    );
    expect(find.text('Titolo movie:1'), findsOneWidget);
  });

  testWidgets('UnknownCodesDoNotCrash', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      delete: [
        _candidate('thing:1', kind: 'Boh', via: ['Strano'], keep: ['X']),
      ],
    );
    await pumpTab(tester);

    expect(find.text('Strano'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RemovingATorrentAsksFirst', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      cleanup: const SpaceCleanup(
        torrents: [
          SpaceTorrent(
            key: 'torrent:abc',
            hash: 'abc',
            name: 'Film.2020.1080p',
            tracker: 'tracker.it',
            sizeBytes: 3000000000,
            ratio: 1.5,
            seedingDays: 12,
            canRemoveNow: true,
          ),
        ],
      ),
    );
    await pumpTab(tester);

    expect(
      find.text('Togli tutti quelli possibili ora (1, 3,00 GB)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Togli'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tolgo i torrent'), findsOneWidget);
    expect(api.calls, isNot(contains('start Torrent torrent:abc')));
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('start Torrent torrent:abc'));
  });

  testWidgets('NarrowLayoutHasNoHorizontalOverflow', (tester) async {
    const long =
        'Un titolo lunghissimo che non finisce mai e va a capo '
        'almeno due volte nella riga stretta';
    api.overviewValue = _overview(
      scannedAt: _scanned,
      topGenres: const ['Dramma'],
      delete: [
        _candidate(
          'movie:1',
          title: long,
          via: ['NobodyWatching', 'NeverOpened', 'LowRating'],
          keep: ['InProgress'],
          genres: ['Dramma'],
        ),
      ],
    );
    await pumpTab(tester, size: const Size(360, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ALinkedFileShowsTheNoteAndNoDelete', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      cleanup: const SpaceCleanup(
        orphans: [
          SpaceFile(
            key: 'file:a',
            path: '/x/a.mkv',
            sizeBytes: 1000000000,
            linked: true,
          ),
          SpaceFile(
            key: 'file:b',
            path: '/x/b.mkv',
            sizeBytes: 1000000000,
            linked: false,
          ),
        ],
      ),
    );
    await pumpTab(tester);

    expect(
      find.text('ha altri collegamenti, non libera spazio'),
      findsOneWidget,
    );
    expect(find.text('Cancella'), findsOneWidget);
    expect(find.text('1,00 GB liberabili ora'), findsOneWidget);
  });

  group('Selezione degli orfani', () {
    SpaceFile orphan(String name, {bool linked = false}) => SpaceFile(
      key: 'file:$name',
      path: '/x/$name.mkv',
      sizeBytes: 1000000000,
      linked: linked,
    );

    SpaceOverview withOrphans(
      List<SpaceFile> orphans, {
      List<SpaceCandidate> delete = const [],
      List<SpaceFile> duplicates = const [],
    }) => _overview(
      scannedAt: _scanned,
      delete: delete,
      cleanup: SpaceCleanup(orphans: orphans, duplicates: duplicates),
    );

    List<String> starts() => [
      for (final c in api.calls)
        if (c.startsWith('start')) c,
    ];

    /// "Seleziona" del gruppo orfani: "Cancellare" viene prima.
    Future<void> selectOrphans(WidgetTester tester) async {
      await tester.tap(find.text('Seleziona').last);
      await tester.pump();
    }

    testWidgets('NoSelectWithOnlyLinkedOrphans', (tester) async {
      api.overviewValue = withOrphans([orphan('a', linked: true)]);
      await pumpTab(tester);
      expect(find.text('Seleziona'), findsNothing);
    });

    testWidgets('CheckboxesOnlyInSelectionAndNotOnLinked', (tester) async {
      api.overviewValue = withOrphans(
        [orphan('a', linked: true), orphan('b'), orphan('c')],
        duplicates: [orphan('d')],
      );
      await pumpTab(tester);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Cancella'), findsNWidgets(3));

      await selectOrphans(tester);
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('file-file:a')),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      expect(
        find.text('ha altri collegamenti, non libera spazio'),
        findsOneWidget,
      );
      // Resta solo il "Cancella" del doppione.
      expect(find.text('Cancella'), findsOneWidget);

      // Un tocco sulla riga sceglie, e il totale somma i GB.
      await tester.tap(find.text('/x/b.mkv'));
      await tester.pump();
      expect(find.text('Elimina selezionati (1 · 1,00 GB)'), findsOneWidget);
      // La riga collegata non si sceglie.
      await tester.tap(find.text('/x/a.mkv'));
      await tester.pump();
      expect(find.text('Elimina selezionati (1 · 1,00 GB)'), findsOneWidget);

      await tester.tap(find.text('Annulla selezione'));
      await tester.pump();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Cancella'), findsNWidgets(3));
    });

    testWidgets('ShiftSelectsTheRangeFromTheLastTapInBothDirections', (
      tester,
    ) async {
      api.overviewValue = withOrphans([
        orphan('a'),
        orphan('b'),
        orphan('linked', linked: true),
        orphan('c'),
        orphan('d'),
      ]);
      await pumpTab(tester);
      await selectOrphans(tester);

      Future<void> tap(String name, {bool shift = false}) async {
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(find.text('/x/$name.mkv'));
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
      }

      // Senza un tocco prima, Maiusc sceglie solo la riga.
      await tap('b', shift: true);
      expect(find.text('Elimina selezionati (1 · 1,00 GB)'), findsOneWidget);

      // In avanti: la riga collegata in mezzo resta fuori.
      await tap('c', shift: true);
      expect(find.text('Elimina selezionati (2 · 2,00 GB)'), findsOneWidget);
      await tap('d', shift: true);
      expect(find.text('Elimina selezionati (3 · 3,00 GB)'), findsOneWidget);

      // All'indietro, da "d".
      await tap('a', shift: true);
      expect(find.text('Elimina selezionati (4 · 4,00 GB)'), findsOneWidget);

      // Senza Maiusc un tocco toglie solo la sua riga.
      await tap('b');
      expect(find.text('Elimina selezionati (3 · 3,00 GB)'), findsOneWidget);
    });

    testWidgets('SelectAllTakesHiddenRowsAndSkipsLinked', (tester) async {
      api.overviewValue = withOrphans([
        orphan('linked', linked: true),
        for (var i = 0; i < 25; i++) orphan('f$i'),
      ]);
      await pumpTab(tester);
      await selectOrphans(tester);
      expect(find.text('Elimina selezionati (0 · 0,00 GB)'), findsOneWidget);

      await tester.tap(find.text('Seleziona tutti'));
      await tester.pump();
      expect(find.text('Elimina selezionati (25 · 25,00 GB)'), findsOneWidget);
      // Sullo schermo la prima pagina: 20 righe, una collegata.
      expect(find.byType(Checkbox), findsNWidgets(19));

      await tester.tap(find.text('Seleziona tutti'));
      await tester.pump();
      expect(find.text('Elimina selezionati (0 · 0,00 GB)'), findsOneWidget);
    });

    testWidgets('ConfirmStartsEachAndAFailureDoesNotStopTheOthers', (
      tester,
    ) async {
      api.overviewValue = withOrphans([
        orphan('a'),
        orphan('b'),
        orphan('c'),
        orphan('skip'),
      ]);
      await pumpTab(tester);
      await selectOrphans(tester);
      for (final name in ['a', 'b', 'c']) {
        await tester.tap(find.text('/x/$name.mkv'));
      }
      await tester.pump();

      api.startFailures['file:a'] = SpaceFailure.busy;
      api.operationResults.add(
        SpaceOperation(
          id: 'op',
          kind: 'Orphan',
          key: 'file:b',
          title: '/x/b.mkv',
          state: 'Running',
          auto: false,
          startedAt: DateTime.utc(2026, 11, 3),
          estimatedFreedBytes: 0,
          pendingBytes: 0,
          steps: const [SpaceStep(name: 'DeleteFile', state: 'Running')],
        ),
      );
      await tester.tap(find.text('Elimina selezionati (3 · 3,00 GB)'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminare 3 file?'), findsOneWidget);
      expect(find.text('Libera subito 3,00 GB.'), findsOneWidget);
      expect(
        find.text('I file si cancellano dal disco: non si torna indietro.'),
        findsOneWidget,
      );
      expect(starts(), isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
      await tester.pump();
      await tester.pump();

      expect(starts(), [
        'start Orphan file:a',
        'start Orphan file:b',
        'start Orphan file:c',
      ]);
      expect(find.text('3 file'), findsOneWidget);
      expect(find.textContaining('Non avviato:'), findsOneWidget);

      // Si esce dalla selezione; chiusa la finestra, si rilegge una volta.
      final reads = api.calls.where((c) => c == 'overview').length;
      await tester.tap(find.text('Chiudi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('Elimina selezionati'), findsNothing);
      expect(api.calls.where((c) => c == 'overview').length, reads + 1);
    });

    testWidgets('CancellingTheConfirmStartsNothing', (tester) async {
      api.overviewValue = withOrphans([orphan('a')]);
      await pumpTab(tester);
      await selectOrphans(tester);
      await tester.tap(find.text('/x/a.mkv'));
      await tester.pump();
      await tester.tap(find.text('Elimina selezionati (1 · 1,00 GB)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Annulla'));
      await tester.pumpAndSettle();

      expect(starts(), isEmpty);
      expect(find.text('Elimina selezionati (1 · 1,00 GB)'), findsOneWidget);
    });

    testWidgets('TheTwoSelectionsExcludeEachOther', (tester) async {
      api.overviewValue = withOrphans(
        [orphan('a')],
        delete: [_candidate('movie:1')],
      );
      await pumpTab(tester);

      await tester.tap(find.text('Seleziona').first);
      await tester.pump();
      await tester.tap(find.text('Titolo movie:1'));
      await tester.pump();
      expect(find.text('Elimina selezionati (1 · 2,00 GB)'), findsOneWidget);
      expect(find.text('Tieni selezionati (1)'), findsOneWidget);

      // Dentro gli orfani: "Cancellare" esce e perde le chiavi.
      await selectOrphans(tester);
      expect(find.text('Tieni selezionati (1)'), findsNothing);
      expect(find.text('Seleziona tutti'), findsOneWidget);
      expect(find.text('Elimina selezionati (0 · 0,00 GB)'), findsOneWidget);
      await tester.tap(find.text('/x/a.mkv'));
      await tester.pump();

      // E viceversa.
      await tester.tap(find.text('Seleziona').first);
      await tester.pump();
      expect(find.text('Seleziona tutti'), findsNothing);
      expect(find.text('Tieni selezionati (0)'), findsOneWidget);
      expect(find.text('Elimina selezionati (0 · 0,00 GB)'), findsOneWidget);

      // Rientrando negli orfani si riparte da zero.
      await selectOrphans(tester);
      expect(find.text('Elimina selezionati (0 · 0,00 GB)'), findsOneWidget);
    });

    testWidgets('AVanishedKeyDoesNotCountAndNoneLeftExits', (tester) async {
      api.overviewValue = withOrphans([orphan('a'), orphan('b')]);
      await pumpTab(tester);
      await selectOrphans(tester);
      await tester.tap(find.text('Seleziona tutti'));
      await tester.pump();
      expect(find.text('Elimina selezionati (2 · 2,00 GB)'), findsOneWidget);

      api.overviewValue = withOrphans([orphan('b')]);
      await tester.tap(find.text('Aggiorna'));
      await tester.pumpAndSettle();
      expect(find.text('Elimina selezionati (1 · 1,00 GB)'), findsOneWidget);

      api.overviewValue = withOrphans([orphan('b', linked: true)]);
      await tester.tap(find.text('Aggiorna'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Elimina selezionati'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Seleziona'), findsNothing);
    });

    testWidgets('EnteringTheSelectionKeepsTheScroll', (tester) async {
      api.overviewValue = withOrphans(
        [for (var i = 0; i < 15; i++) orphan('f$i')],
        delete: [for (var i = 0; i < 20; i++) _candidate('movie:$i')],
      );
      await pumpTab(tester, size: const Size(1440, 800));

      double pixels() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      await tester.dragUntilVisible(
        find.text('File orfani'),
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final before = pixels();
      expect(before, greaterThan(0));

      await tester.tap(find.text('Seleziona').last);
      await tester.pumpAndSettle();
      expect(find.text('Seleziona tutti'), findsOneWidget);
      expect(pixels(), before);
    });
  });

  SpaceLighten lightenWith(SpaceLightenDownload? d) => SpaceLighten(
    key: 'movie:1',
    kind: 'Movie',
    title: 'Film',
    sizeBytes: 9000000000,
    excessBytes: 5000000000,
    gbPerHour: 6.5,
    download: d,
  );

  Future<void> pumpLighten(WidgetTester tester, SpaceLightenDownload? d) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      lighten: [lightenWith(d)],
    );
    await pumpTab(tester);
  }

  testWidgets('ADownloadingLightenRowShowsProgress', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Downloading',
        progress: 0.75,
        sizeLeftBytes: 1000000000,
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(find.text('In download 75 %'), findsOneWidget);
    expect(find.text('1,00 GB rimanenti'), findsOneWidget);
    expect(find.text('Alleggerisci'), findsNothing);
  });

  testWidgets('ImportingShowsTheLabel', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Importing',
        progress: 1,
        sizeLeftBytes: 0,
      ),
    );
    expect(find.text('In importazione'), findsOneWidget);
    expect(find.text('Alleggerisci'), findsNothing);
  });

  testWidgets('AFailedDownloadShowsTheButtonAgain', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Failed',
        progress: 0,
        sizeLeftBytes: 0,
      ),
    );
    expect(find.text('Download non riuscito'), findsOneWidget);
    expect(find.text('Alleggerisci'), findsOneWidget);
  });

  testWidgets('ABlockedMovieShowsRadarrTheMessageAndImport', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Blocked',
        progress: 1,
        sizeLeftBytes: 0,
        message: 'Not an upgrade for existing movie file',
      ),
    );
    expect(find.text('Radarr non lo importa da solo'), findsOneWidget);
    expect(find.text('Not an upgrade for existing movie file'), findsOneWidget);
    expect(find.text('Importa'), findsOneWidget);
    expect(find.text('Alleggerisci'), findsNothing);
  });

  testWidgets('ABlockedSeasonSaysSonarr', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      lighten: const [
        SpaceLighten(
          key: 'season:142:1',
          kind: 'Season',
          title: 'Serie',
          seasonNumber: 1,
          sizeBytes: 9000000000,
          excessBytes: 5000000000,
          gbPerHour: 6.5,
          download: SpaceLightenDownload(
            state: 'Blocked',
            progress: 1,
            sizeLeftBytes: 0,
          ),
        ),
      ],
    );
    await pumpTab(tester);
    expect(find.text('Sonarr non lo importa da solo'), findsOneWidget);
    expect(find.text('Importa'), findsOneWidget);
  });

  testWidgets('ImportShowsTheSpinnerThenRereads', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Blocked',
        progress: 1,
        sizeLeftBytes: 0,
      ),
    );
    final gate = api.actionGate = Completer<void>();
    final reads = api.calls.where((c) => c == 'overview').length;
    final button = find.byKey(const ValueKey('space-lighten-import'));
    await tester.tap(button);
    await tester.pump();

    expect(api.calls, contains('import movie:1'));
    expect(
      find.descendant(
        of: button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.descendant(
              of: button,
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          )
          .onPressed,
      isNull,
    );

    api.overviewValue = _overview(
      scannedAt: _scanned,
      lighten: [
        lightenWith(
          const SpaceLightenDownload(
            state: 'Importing',
            progress: 1,
            sizeLeftBytes: 0,
          ),
        ),
      ],
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c == 'overview').length, greaterThan(reads));
    expect(find.text('In importazione'), findsOneWidget);
    expect(button, findsNothing);
  });

  testWidgets('AFailedImportShowsTheCode', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Blocked',
        progress: 1,
        sizeLeftBytes: 0,
      ),
    );
    Future<void> importFailing(SpaceException error) async {
      api.nextImportError = error;
      await tester.tap(find.byKey(const ValueKey('space-lighten-import')));
      await tester.pumpAndSettle();
    }

    // Il prossimo avviso aspetta che il precedente se ne vada.
    Future<void> waitSnackBar() async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    await importFailing(const SpaceException(SpaceFailure.server, 'NoFiles'));
    expect(
      find.text(
        "Import non riuscito: nel download non c'è un file da importare",
      ),
      findsOneWidget,
    );
    await waitSnackBar();

    await importFailing(
      const SpaceException(SpaceFailure.server, 'Unreachable'),
    );
    expect(find.text('Import non riuscito (Unreachable)'), findsOneWidget);
    await waitSnackBar();

    // Niente più da importare: la riga è vecchia, si rilegge.
    final reads = api.calls.where((c) => c == 'overview').length;
    await importFailing(const SpaceException(SpaceFailure.unknown, 'Unknown'));
    expect(find.text("Non c'è più niente da importare"), findsOneWidget);
    expect(api.calls.where((c) => c == 'overview').length, reads + 1);
  });

  testWidgets('PollingIsFastWhileDownloading', (tester) async {
    await pumpLighten(
      tester,
      const SpaceLightenDownload(
        state: 'Downloading',
        progress: 0.1,
        sizeLeftBytes: 5,
      ),
    );
    final before = api.calls.where((c) => c == 'overview').length;
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls.where((c) => c == 'overview').length, greaterThan(before));
  });

  testWidgets('LightenRowOpensTheReducedCard', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      lighten: const [
        SpaceLighten(
          key: 'movie:1',
          kind: 'Movie',
          title: 'Film',
          sizeBytes: 9000000000,
          excessBytes: 5000000000,
          gbPerHour: 6.5,
        ),
      ],
    );
    await pumpTab(tester);

    await tester.tap(find.text('Film'));
    await tester.pumpAndSettle();

    expect(find.text('Tienilo'), findsOneWidget);
    expect(find.text('Elimina'), findsNothing);
    expect(find.text('Alleggerisci'), findsNWidgets(2));
    await tester.tap(find.text('Tienilo'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('keep movie:1 Film'));
  });

  testWidgets('CleanupGroupsAndTotals', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      delete: [_candidate('movie:1')],
      cleanup: const SpaceCleanup(
        torrents: [
          SpaceTorrent(
            key: 't:1',
            hash: '1',
            name: 'Uno',
            tracker: 'x',
            sizeBytes: 3000000000,
            ratio: 1,
            seedingDays: 3,
            canRemoveNow: true,
          ),
          SpaceTorrent(
            key: 't:2',
            hash: '2',
            name: 'Due',
            tracker: 'x',
            sizeBytes: 1000000000,
            ratio: 1,
            seedingDays: 3,
            canRemoveNow: false,
          ),
        ],
        orphans: [
          SpaceFile(
            key: 'f:1',
            path: '/o',
            sizeBytes: 1000000000,
            linked: false,
          ),
        ],
        duplicates: [
          SpaceFile(
            key: 'f:2',
            path: '/d',
            sizeBytes: 1000000000,
            linked: false,
          ),
        ],
      ),
    );
    await pumpTab(tester);

    for (final s in [
      'Si possono togliere ora',
      'In seed obbligatorio',
      'File orfani',
      'Doppioni',
      'dopo il seed',
      'subito 2,00 GB · dopo il seed 0,00 GB',
      '5,00 GB liberabili ora',
    ]) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
  });

  testWidgets('ASeriesRowIsNeverGrouped', (tester) async {
    api.overviewValue = _overview(
      scannedAt: _scanned,
      delete: [
        _candidate(
          'series:7',
          title: 'Serie Intera',
          kind: 'Series',
          seriesKey: 'series:7',
        ),
        _candidate(
          'season:7:1',
          title: 'Serie Lunga',
          kind: 'Season',
          season: 1,
          seriesKey: 'series:7',
        ),
        _candidate(
          'season:7:2',
          title: 'Serie Lunga',
          kind: 'Season',
          season: 2,
          seriesKey: 'series:7',
        ),
      ],
    );
    await pumpTab(tester);

    expect(find.text('Serie Intera'), findsOneWidget);
    expect(find.text('Serie Lunga'), findsOneWidget);
    await tester.tap(find.text('Serie Lunga'));
    await tester.pump();
    expect(find.text('Stagione 2'), findsOneWidget);
  });
}
