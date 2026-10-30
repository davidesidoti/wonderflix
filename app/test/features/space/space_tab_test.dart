import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) => SpaceOverview(
  scannedAt: scannedAt,
  scanning: scanning,
  quota: const SpaceQuota(usedBytes: 3000000000000, limitBytes: 4000000000000),
  breakdown: SpaceOverview.empty.breakdown,
  delete: delete,
  lighten: lighten,
  cleanup: cleanup,
  pending: const [],
  kept: const [],
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
