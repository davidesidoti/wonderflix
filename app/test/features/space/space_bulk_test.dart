import 'dart:async';

import 'package:flutter/material.dart';
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

const _gb = 1000000000;

SpaceCandidate _candidate(
  String key, {
  String? title,
  String kind = 'Movie',
  int? season,
  String? seriesKey,
  int now = 2 * _gb,
  int later = 0,
  int pack = 0,
}) => SpaceCandidate(
  key: key,
  kind: kind,
  title: title ?? 'Titolo $key',
  seasonNumber: season,
  seriesKey: seriesKey,
  sizeBytes: now + later,
  freeNowBytes: now,
  freeLaterBytes: later,
  inPackBytes: pack,
  via: const [],
  keep: const [],
  viewers: const [],
  requests: const [],
  ratingCount: 0,
  genres: const [],
);

SpaceCandidate _season(int n) => _candidate(
  'season:7:$n',
  title: 'Serie Lunga',
  kind: 'Season',
  season: n,
  seriesKey: 'series:7',
);

SpaceOverview _overview(List<SpaceCandidate> delete) => SpaceOverview(
  scannedAt: DateTime.now().subtract(const Duration(hours: 2)),
  scanning: false,
  quota: null,
  breakdown: SpaceOverview.empty.breakdown,
  delete: delete,
  lighten: const [],
  cleanup: const SpaceCleanup(),
  pending: const [],
  kept: const [],
  operations: const [],
  topGenres: const [],
  errors: const SpaceErrors(),
);

SpaceOperation _op(
  String id,
  String state,
  List<SpaceStep> steps, {
  int freed = 0,
  int pending = 0,
}) => SpaceOperation(
  id: id,
  kind: 'Movie',
  key: 'movie:$id',
  title: 'Op $id',
  state: state,
  auto: false,
  startedAt: DateTime.utc(2026, 10, 30),
  estimatedFreedBytes: freed,
  pendingBytes: pending,
  steps: steps,
);

SpaceStep _step(String name, String state) =>
    SpaceStep(name: name, state: state);

void main() {
  late FakeSpaceApi api;

  setUp(() => api = FakeSpaceApi());

  Future<void> pumpTab(
    WidgetTester tester,
    List<SpaceCandidate> delete, {
    Size size = const Size(1440, 4000),
  }) async {
    api.overviewValue = _overview(delete);
    await pumpApp(
      tester,
      const Scaffold(body: SpaceTab()),
      overrides: [
        ...adminTestOverrides(
          FakeAdminApi(),
          downloads: FakeDownloadsApi(),
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

  Finder checkboxes() => find.byType(Checkbox);

  List<bool?> values(WidgetTester tester) => [
    for (final c in tester.widgetList<Checkbox>(checkboxes())) c.value,
  ];

  /// "Elimina selezionati", poi "Elimina" nella panoramica.
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.textContaining('Elimina selezionati'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pump();
    await tester.pump();
  }

  int reads() => api.calls.where((c) => c.startsWith('operation')).length;
  int overviews() => api.calls.where((c) => c == 'overview').length;
  List<String> starts() => [
    for (final c in api.calls)
      if (c.startsWith('start')) c,
  ];

  testWidgets('SelectModeShowsCheckboxesAndTheBar', (tester) async {
    await pumpTab(tester, [_candidate('movie:1'), _candidate('movie:2')]);
    expect(checkboxes(), findsNothing);

    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    expect(checkboxes(), findsNWidgets(2));
    expect(find.text('Elimina selezionati (0 · 0,00 GB)'), findsOneWidget);

    // In selezione un tocco sulla riga sceglie, non apre la scheda.
    await tester.tap(find.text('Titolo movie:1'));
    await tester.tap(find.text('Titolo movie:2'));
    await tester.pumpAndSettle();
    expect(values(tester), [true, true]);
    expect(find.text('Elimina selezionati (2 · 4,00 GB)'), findsOneWidget);

    // Una riga che sparisce esce dalla selezione.
    api.overviewValue = _overview([_candidate('movie:1')]);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.text('Elimina selezionati (1 · 2,00 GB)'), findsOneWidget);
  });

  testWidgets('SelectingAGroupSelectsItsSeasonsOnce', (tester) async {
    await pumpTab(tester, [_season(1), _season(2), _candidate('movie:1')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();

    final group = find.descendant(
      of: find.byKey(const ValueKey('series-series:7')),
      matching: find.byType(Checkbox),
    );
    await tester.tap(group.first);
    await tester.pump();
    expect(find.text('Elimina selezionati (2 · 4,00 GB)'), findsOneWidget);

    // Aperta, le stagioni sono già scelte; sceglierne una non la raddoppia.
    await tester.tap(find.text('Serie Lunga'));
    await tester.pump();
    expect(values(tester), [true, true, true, false]);
    await tester.tap(find.text('Stagione 1'));
    await tester.pump();
    expect(values(tester), [null, false, true, false]);
    await tester.tap(group.first);
    await tester.pump();
    expect(find.text('Elimina selezionati (2 · 4,00 GB)'), findsOneWidget);

    api.operationResults.add(_op('x', 'Done', const []));
    await confirm(tester);
    expect(starts(), ['start Season season:7:1', 'start Season season:7:2']);
  });

  testWidgets('TheSummaryListsTitlesAndTotals', (tester) async {
    await pumpTab(tester, [
      _candidate('movie:1', title: 'Film Raro', later: _gb, pack: _gb ~/ 2),
      _season(3),
    ]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Film Raro'));
    await tester.tap(find.text('Serie Lunga · Stagione 3'));
    await tester.pump();
    await tester.tap(find.textContaining('Elimina selezionati'));
    await tester.pumpAndSettle();

    expect(find.text('Eliminare 2 titoli?'), findsOneWidget);
    final dialog = find.byType(Dialog);
    Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
    expect(inDialog(find.text('Film Raro')), findsOneWidget);
    expect(inDialog(find.text('Serie Lunga · Stagione 3')), findsOneWidget);
    expect(
      inDialog(find.text('subito 2,00 GB · dopo il seed 1,00 GB')),
      findsOneWidget,
    );
    expect(find.text('Libera subito 4,00 GB.'), findsOneWidget);
    expect(find.text('Altri 1,00 GB dopo il seed.'), findsOneWidget);
    expect(find.textContaining('0,50 GB restano'), findsOneWidget);
    expect(find.text('Per i film'), findsOneWidget);
    expect(find.text('Per le stagioni'), findsOneWidget);
    expect(find.textContaining('Elimino da Radarr con i file'), findsOneWidget);
    expect(
      find.textContaining('Smetto di monitorare la stagione'),
      findsOneWidget,
    );

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(starts(), isEmpty);
    expect(find.text('Elimina selezionati (2 · 4,00 GB)'), findsOneWidget);
  });

  testWidgets('StartsOneOperationPerTitleInOrder', (tester) async {
    await pumpTab(tester, [
      _candidate('movie:1'),
      _candidate('movie:2'),
      _candidate('movie:3'),
    ]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:3'));
    await tester.tap(find.text('Titolo movie:1'));
    await tester.pump();

    api.startGate = Completer<void>();
    api.operationResults.add(_op('x', 'Done', const []));
    await confirm(tester);
    // Uno alla volta: il secondo parte quando il primo ha risposto.
    expect(starts(), ['start Movie movie:1']);
    api.startGate!.complete();
    await tester.pumpAndSettle();
    expect(starts(), ['start Movie movie:1', 'start Movie movie:3']);
  });

  testWidgets('TheBarButtonIsOffWhileStartsRun', (tester) async {
    await pumpTab(tester, [_candidate('movie:1'), _candidate('movie:2')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:1'));
    await tester.tap(find.text('Titolo movie:2'));
    await tester.pump();

    api.startGate = Completer<void>();
    api.operationResults.add(_op('x', 'Done', const []));
    await confirm(tester);
    expect(starts(), ['start Movie movie:1']);

    // Una seconda pressione non apre una seconda panoramica.
    await tester.tap(
      find.textContaining('Elimina selezionati'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Eliminare 2 titoli?'), findsNothing);

    api.startGate!.complete();
    await tester.pumpAndSettle();
    expect(starts(), hasLength(2));
  });

  testWidgets('ABusyTitleDoesNotStopTheOthers', (tester) async {
    await pumpTab(tester, [_candidate('movie:1'), _candidate('movie:2')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:1'));
    await tester.tap(find.text('Titolo movie:2'));
    await tester.pump();

    api.startFailures['movie:1'] = SpaceFailure.busy;
    api.operationResults.add(
      _op('op1', 'Running', [_step('FindTorrents', 'Running')]),
    );
    await confirm(tester);
    await tester.pump();

    expect(starts(), hasLength(2));
    expect(
      find.text("Non avviato: Su questo titolo c'è già un'operazione in corso"),
      findsOneWidget,
    );
    expect(find.text('Cerco i torrent'), findsOneWidget);
    expect(api.calls, contains('operation op1'));
  });

  testWidgets('StepsOfAllTitlesAreShownLive', (tester) async {
    await pumpTab(tester, [_candidate('movie:1'), _candidate('movie:2')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:1'));
    await tester.tap(find.text('Titolo movie:2'));
    await tester.pump();

    api.operationResultsById['op1'] = [
      _op('op1', 'Running', [_step('FindTorrents', 'Running')]),
      _op('op1', 'Done', [_step('FindTorrents', 'Done')], freed: 2 * _gb),
    ];
    api.operationResultsById['op2'] = [
      _op('op2', 'Running', [_step('DeleteFromRadarr', 'Running')]),
      _op('op2', 'Running', [_step('DeleteFromRadarr', 'Running')]),
      _op(
        'op2',
        'Done',
        [_step('DeleteFromRadarr', 'Done')],
        freed: 3 * _gb,
        pending: _gb,
      ),
    ];
    await confirm(tester);
    await tester.pump();
    // La panoramica sta ancora uscendo: la finestra dei passi è l'ultima.
    final dialog = find.byType(Dialog).last;
    Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
    expect(inDialog(find.text('Titolo movie:1')), findsOneWidget);
    expect(inDialog(find.text('Titolo movie:2')), findsOneWidget);
    expect(inDialog(find.text('In corso')), findsNWidgets(2));
    expect(find.text('Cerco i torrent'), findsOneWidget);
    expect(find.text('Elimino da Radarr con i file'), findsOneWidget);
    final before = overviews();

    await tester.pump(const Duration(seconds: 1));
    expect(inDialog(find.text('Finita')), findsOneWidget);
    expect(find.textContaining('Liberati'), findsNothing);
    expect(overviews(), before);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(inDialog(find.text('Finita')), findsNWidgets(2));
    expect(find.text('Liberati 5,00 GB'), findsOneWidget);
    expect(find.text('1,00 GB in attesa del seed'), findsOneWidget);
    expect(overviews(), before + 1);

    final done = reads();
    await tester.pump(const Duration(seconds: 3));
    expect(reads(), done);
    expect(overviews(), before + 1);
  });

  testWidgets('ClosingTheBulkDialogStopsPolling', (tester) async {
    await pumpTab(tester, [_candidate('movie:1'), _candidate('movie:2')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:1'));
    await tester.tap(find.text('Titolo movie:2'));
    await tester.pump();

    api.operationResults.add(
      _op('x', 'Running', [_step('FindTorrents', 'Running')]),
    );
    await confirm(tester);
    await tester.pump(const Duration(seconds: 1));
    final open = reads();
    final before = overviews();
    expect(open, greaterThanOrEqualTo(2));

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(reads(), open);
    // Chiusa la finestra la panoramica si rilegge una volta sola.
    expect(overviews(), before + 1);
  });

  testWidgets('TheBarCountsASeriesWithoutItsSeasons', (tester) async {
    await pumpTab(tester, [
      _candidate(
        'series:7',
        title: 'Serie Lunga',
        kind: 'Series',
        now: 5 * _gb,
      ),
      _season(1),
      _season(2),
    ]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    for (final cb in checkboxes().evaluate().toList()) {
      await tester.tap(find.byWidget(cb.widget));
    }
    await tester.pump();
    expect(find.text('Elimina selezionati (1 · 5,00 GB)'), findsOneWidget);
  });

  testWidgets('NoBarWhenTheDeleteListEmpties', (tester) async {
    await pumpTab(tester, [_candidate('movie:1')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    expect(find.textContaining('Elimina selezionati'), findsOneWidget);

    api.overviewValue = _overview(const []);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.textContaining('Elimina selezionati'), findsNothing);

    api.overviewValue = _overview([_candidate('movie:2')]);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.textContaining('Elimina selezionati'), findsNothing);
    expect(find.text('Seleziona'), findsOneWidget);
  });

  testWidgets('CancelSelectionClears', (tester) async {
    await pumpTab(tester, [_candidate('movie:1'), _candidate('movie:2')]);
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:1'));
    await tester.pump();
    expect(find.text('Elimina selezionati (1 · 2,00 GB)'), findsOneWidget);

    await tester.tap(find.text('Annulla selezione'));
    await tester.pump();
    expect(checkboxes(), findsNothing);
    expect(find.textContaining('Elimina selezionati'), findsNothing);

    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    expect(values(tester), [false, false]);
  });

  testWidgets('NarrowLayoutHasNoOverflow', (tester) async {
    await pumpTab(tester, [
      for (var i = 1; i <= 12; i++) _candidate('movie:$i'),
    ], size: const Size(360, 700));
    await tester.tap(find.text('Seleziona'));
    await tester.pump();
    await tester.tap(find.text('Titolo movie:1'));
    await tester.pump();
    expect(find.text('Annulla selezione'), findsOneWidget);

    api.operationResults.add(
      _op('x', 'Running', [_step('FindTorrents', 'Running')]),
    );
    await confirm(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Cerco i torrent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
