import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/features/downloads/download_search_controller.dart';
import 'package:wonderflix/features/downloads/download_search_page.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/space/space_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/download_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/space_fakes.dart';

DownloadSearch _search({
  DownloadCurrentFile? current,
  List<DownloadCandidate>? candidates,
  List<DownloadRejected> rejected = const [],
  String? error,
  String? externalSearchUrl,
  List<DownloadEpisodeChoice> episodeChoices = const [],
}) =>
    DownloadSearch(
      key: 'movie:1',
      kind: DownloadKind.movie,
      title: 'Film',
      runtimeMinutes: 100,
      current: current,
      candidates: candidates ?? [testCandidate()],
      rejected: rejected,
      validCount: 1,
      totalCount: 2,
      error: error,
      externalSearchUrl: externalSearchUrl,
      episodeChoices: episodeChoices,
    );

/// Una riga con questo peso e punteggio; `g1` è la scelta della regola.
DownloadCandidate _row(String guid, int sizeBytes, {int score = 120}) =>
    DownloadCandidate(
      rank: guid == 'g1' ? 1 : 2,
      release: DownloadRelease(
        guid: guid,
        indexerId: 3,
        indexer: 'Idx',
        title: 'Film.$guid',
        quality: 'x',
        resolution: 1080,
        sizeBytes: sizeBytes,
        score: score,
      ),
      isChoice: guid == 'g1',
      wouldImport: true,
    );

const _confirmTitle = 'Scaricare questa release?';
const _current120 =
    DownloadCurrentFile(sizeBytes: 1000000000, score: 120, quality: 'x');

void main() {
  late FakeDownloadsApi api;
  late FakeSpaceApi space;

  setUp(() {
    api = FakeDownloadsApi();
    space = FakeSpaceApi();
  });

  /// Una pagina con un pulsante che apre la ricerca. Con [settle] falso si
  /// ferma durante l'attesa (lo spinner non si assesta mai).
  Future<void> open(
    WidgetTester tester, {
    bool reviewing = false,
    bool lighten = false,
    bool settle = true,
    Size size = const Size(1440, 900),
    SocialFeatures features =
        const SocialFeatures(inbox: true, downloads: true),
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDownloadSearch(context, 'movie:1', 'Film',
                reviewing: reviewing, lighten: lighten),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        ...adminTestOverrides(FakeAdminApi(),
            downloads: api,
            features: features),
        spaceApiProvider.overrideWithValue(space),
      ],
      surfaceSize: size,
    );
    await tester.tap(find.text('apri'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Future<void> tapGrab(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Scarica').first);
    await tester.pumpAndSettle();
  }

  List<String> grabs() => api.calls.where((c) => c.startsWith('grab')).toList();

  testWidgets('TheChoiceIsHighlightedWithItsReason', (tester) async {
    await open(tester);

    expect(find.text('Il più leggero tra quelli con punteggio 120 in 1080p'),
        findsOneWidget);
    expect(find.text('1 risultati validi su 1'), findsOneWidget);
    final box = tester.widget<Container>(find
        .ancestor(
            of: find.widgetWithText(FilledButton, 'Scarica'),
            matching: find.byType(Container))
        .first);
    expect((box.decoration! as BoxDecoration).color, const Color(0xFF2B2418));
  });

  testWidgets('RejectedAreGreyWithTheirReason', (tester) async {
    api.searchValue = _search(rejected: [
      DownloadRejected(
          release: testRelease(guid: 'r1'),
          reason: RejectedReason.arr,
          detail: 'Già nel catalogo'),
      DownloadRejected(
          release: testRelease(guid: 'r2'),
          reason: RejectedReason.tooSmall,
          detail: '0.62'),
    ]);
    await open(tester);

    expect(find.text('Scartati · 2'), findsOneWidget);
    expect(find.textContaining('Già nel catalogo'), findsOneWidget);
    expect(find.textContaining('0,62 GB/ora, sotto la soglia'), findsOneWidget);
  });

  group('ExternalSearch', () {
    const url = 'https://mircrew.example/search?q=Film';

    testWidgets('without candidates and with a URL the button is there, '
        'with the rejected below', (tester) async {
      api.searchValue = _search(
          candidates: const [],
          externalSearchUrl: url,
          rejected: [
            DownloadRejected(
                release: testRelease(guid: 'r1'),
                reason: RejectedReason.arr,
                detail: 'Già nel catalogo'),
          ]);
      await open(tester);

      expect(find.text('Niente da mostrare'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cerca su MIRCrew'),
          findsOneWidget);
      expect(find.text('Scartati · 1'), findsOneWidget);
    });

    testWidgets('without a URL there is no button', (tester) async {
      api.searchValue = _search(candidates: const []);
      await open(tester);

      expect(find.text('Niente da mostrare'), findsOneWidget);
      expect(find.text('Cerca su MIRCrew'), findsNothing);
    });

    testWidgets('with candidates there is no button', (tester) async {
      api.searchValue = _search(externalSearchUrl: url);
      await open(tester);

      expect(find.text('Cerca su MIRCrew'), findsNothing);
    });
  });

  testWidgets('ALowerScoreAsksFirst', (tester) async {
    api.searchValue = _search(current: _current120);
    await open(tester);

    await tapGrab(tester);
    expect(find.text(_confirmTitle), findsOneWidget);
    expect(find.textContaining('non supera'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(grabs(), isEmpty);

    await tapGrab(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Scarica').last);
    await tester.pumpAndSettle();
    expect(grabs(), ['grab movie:1 g1 3']);
  });

  testWidgets('ANonImportAsksFirst', (tester) async {
    api.searchValue = _search(candidates: [
      DownloadCandidate(
          rank: 1,
          release: testRelease(),
          isChoice: true,
          wouldImport: false),
    ]);
    await open(tester);

    await tapGrab(tester);
    expect(find.text(_confirmTitle), findsOneWidget);
    expect(find.textContaining('importarla a mano'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(grabs(), isEmpty);
  });

  testWidgets('a clean grab starts the download and closes the page',
      (tester) async {
    await open(tester);

    await tapGrab(tester);

    expect(find.text(_confirmTitle), findsNothing);
    expect(grabs(), ['grab movie:1 g1 3']);
    expect(find.text('Download avviato'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('GrabIsDisabledWhileRunning', (tester) async {
    api.searchValue = _search(candidates: [
      testCandidate(),
      testCandidate(rank: 2, guid: 'g2'),
    ]);
    await open(tester, reviewing: true);
    api.actionGate = Completer<void>();

    await tester.tap(find.widgetWithText(FilledButton, 'Scarica').first);
    await tester.pump();

    // Anche l'altra release e "Va bene così".
    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    expect(buttons, hasLength(3));
    expect(buttons.map((b) => b.onPressed), everyElement(isNull));
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Ricerca di nuovo'))
            .onPressed,
        isNull);
    expect(grabs(), hasLength(1));

    api.actionGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('ExpiredKeepsThePage', (tester) async {
    api.nextActionFailure = DownloadsFailure.expired;
    await open(tester);

    await tapGrab(tester);

    expect(find.text("Questa release non c'è più: ricerca di nuovo"),
        findsWidgets);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Scarica'), findsOneWidget);
  });

  for (final (failure, text) in [
    (
      DownloadsFailure.busy,
      'Un altro download di questo titolo è in corso: riprova tra poco',
    ),
    (DownloadsFailure.arrUnavailable, 'Radarr o Sonarr non rispondono'),
    (DownloadsFailure.refused, 'Sonarr o Radarr non sono riusciti a passarlo al client di download (per esempio il torrent è già in qBittorrent)'),
  ]) {
    testWidgets('BusyAndArrDownShowAMessage ${failure.name}', (tester) async {
      api.nextActionFailure = failure;
      await open(tester);

      await tapGrab(tester);

      expect(find.text(text), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
    });
  }

  group('ExistingTorrent', () {
    const existingMessage =
        'Il torrent "Film.2024.1080p" è già in qBittorrent. Importo i suoi file? Sostituiranno quelli in libreria.';

    List<String> imports() =>
        api.calls.where((c) => c.startsWith('importExisting')).toList();

    Future<void> grabExisting(WidgetTester tester,
        {bool lighten = false}) async {
      api.nextActionFailure = DownloadsFailure.refused;
      api.nextActionExisting =
          const ExistingTorrent(hash: 'abc', name: 'Film.2024.1080p');
      await open(tester, lighten: lighten);
      await tapGrab(tester);
    }

    testWidgets('asks whether to import, with the torrent name',
        (tester) async {
      await grabExisting(tester);

      expect(find.text('Già in qBittorrent'), findsOneWidget);
      expect(find.text(existingMessage), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Importa'), findsOneWidget);
      expect(imports(), isEmpty);
    });

    testWidgets('cancel imports nothing and shows no error', (tester) async {
      await grabExisting(tester);

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(imports(), isEmpty);
      expect(find.text('Già in qBittorrent'), findsNothing);
      expect(find.textContaining('per esempio il torrent'), findsNothing);
      // La pagina resta.
      expect(find.widgetWithText(FilledButton, 'Scarica'), findsOneWidget);
    });

    testWidgets('confirm imports and closes the page', (tester) async {
      await grabExisting(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Importa'));
      await tester.pumpAndSettle();

      expect(imports(), ['importExisting movie:1 abc']);
      expect(find.text('Import avviato'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Scarica'), findsNothing);
    });

    testWidgets('an import from Alleggerisci tells the plugin', (tester) async {
      await grabExisting(tester, lighten: true);

      await tester.tap(find.widgetWithText(FilledButton, 'Importa'));
      await tester.pumpAndSettle();

      expect(imports(), ['importExisting movie:1 abc lighten']);
    });

    testWidgets('an import error keeps the page open', (tester) async {
      await grabExisting(tester);
      api.nextActionFailure = DownloadsFailure.noFiles;

      await tester.tap(find.widgetWithText(FilledButton, 'Importa'));
      await tester.pumpAndSettle();

      expect(imports(), ['importExisting movie:1 abc']);
      expect(find.text('Import avviato'), findsNothing);
      expect(find.text("Nel download non c'è un file da importare"), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Scarica'), findsOneWidget);
    });

    testWidgets('a refusal without an existing torrent shows the error',
        (tester) async {
      api.nextActionFailure = DownloadsFailure.refused;
      await open(tester);
      await tapGrab(tester);

      expect(find.text('Già in qBittorrent'), findsNothing);
      expect(find.textContaining('per esempio il torrent'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Scarica'), findsOneWidget);
    });
  });

  testWidgets('AcceptOnlyWhenReviewing', (tester) async {
    await open(tester);
    expect(find.text('Va bene così'), findsNothing);
  });

  testWidgets('AcceptWhenReviewing closes the page', (tester) async {
    await open(tester, reviewing: true);

    await tester.tap(find.text('Va bene così'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('accept movie:1'));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('ClosingDuringASearchIsQuiet', (tester) async {
    api.searchGate = Completer<DownloadSearch>();
    await open(tester, settle: false);
    expect(find.text('Cerco su Radarr/Sonarr, può volerci un minuto'),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NarrowLayoutHasNoHorizontalOverflow', (tester) async {
    api.searchValue = _search(current: _current120, candidates: [
      for (var i = 1; i <= 3; i++) testCandidate(rank: i, guid: 'g$i'),
    ]);
    await open(tester, size: const Size(375, 800));

    expect(tester.takeException(), isNull);
    // Una scheda per release: niente intestazione di tabella.
    expect(find.text('Release'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Scarica'), findsNWidgets(3));
  });

  group('best episodes box', () {
    DownloadSearch season(List<DownloadEpisodeChoice> choices) =>
        testSeasonSearch(choices, 'movie:1');

    Finder grabAllButton(String label) =>
        find.widgetWithText(FilledButton, label);

    testWidgets('is hidden without episode choices', (tester) async {
      await open(tester);

      expect(find.text('Migliori episodi'), findsNothing);
      expect(find.textContaining('Scarica tutti'), findsNothing);
    });

    testWidgets('lists one row per episode and "nessun file valido"',
        (tester) async {
      api.searchValue = season([
        testEpisodeChoice(1),
        testEpisodeChoice(2, hasRelease: false),
        testEpisodeChoice(3),
      ]);
      await open(tester);

      expect(find.text('Migliori episodi'), findsOneWidget);
      expect(find.text('E1'), findsOneWidget);
      expect(find.text('E2'), findsOneWidget);
      expect(find.text('nessun file valido'), findsOneWidget);
      // N = solo gli episodi con un singolo.
      expect(grabAllButton('Scarica tutti (2)'), findsOneWidget);
      // Un "Scarica" per i due singoli e uno per la lista completa sotto.
      expect(find.widgetWithText(FilledButton, 'Scarica'), findsNWidgets(3));
    });

    testWidgets('no single at all: no "Scarica tutti"', (tester) async {
      api.searchValue = season([testEpisodeChoice(1, hasRelease: false)]);
      await open(tester);

      expect(find.text('nessun file valido'), findsOneWidget);
      expect(find.textContaining('Scarica tutti'), findsNothing);
    });

    testWidgets('a row "Scarica" grabs that episode like today',
        (tester) async {
      api.searchValue = season([testEpisodeChoice(1), testEpisodeChoice(2)]);
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Scarica').at(1));
      await tester.pumpAndSettle();

      expect(grabs(), ['grab movie:1 e2 3']);
      expect(find.text('Download avviato'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('"Scarica tutti" grabs in order with progress, then closes',
        (tester) async {
      api.searchValue = season([for (var n = 1; n <= 3; n++) testEpisodeChoice(n)]);
      await open(tester);
      api.actionGates.addAll([for (var i = 0; i < 3; i++) Completer<void>()]);
      final gates = [...api.actionGates];

      await tester.tap(grabAllButton('Scarica tutti (3)'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Scarico 1/3'), findsOneWidget);
      // Tutti i pulsanti spenti, anche "Ricerca di nuovo".
      expect(
          tester
              .widgetList<FilledButton>(find.byType(FilledButton))
              .map((b) => b.onPressed),
          everyElement(isNull));
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Ricerca di nuovo'))
              .onPressed,
          isNull);

      gates[0].complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Scarico 2/3'), findsOneWidget);

      gates[1].complete();
      gates[2].complete();
      await tester.pumpAndSettle();

      expect(grabs(),
          ['grab movie:1 e1 3', 'grab movie:1 e2 3', 'grab movie:1 e3 3']);
      expect(find.text('3 download avviati'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a failure keeps the page open with the summary',
        (tester) async {
      api.searchValue = season([for (var n = 1; n <= 3; n++) testEpisodeChoice(n)]);
      await open(tester);
      api.nextActionFailure = DownloadsFailure.refused;

      await tester.tap(grabAllButton('Scarica tutti (3)'));
      await tester.pumpAndSettle();

      expect(grabs(), hasLength(3));
      // Come negli altri test: il testo si trova due volte (SnackBar della pagina).
      expect(find.textContaining('2 avviati, 1 no: Sonarr o Radarr'), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
      // Resta solo E1, quello fallito: E2 ed E3 sono partiti e non si
      // riscaricano.
      expect(find.text('E1'), findsOneWidget);
      expect(find.text('E2'), findsNothing);
      expect(find.text('E3'), findsNothing);
      expect(grabAllButton('Scarica tutti (1)'), findsOneWidget);

      await tester.tap(grabAllButton('Scarica tutti (1)'));
      await tester.pumpAndSettle();
      expect(grabs().skip(3), ['grab movie:1 e1 3']);
      // Partito l'ultimo, la pagina si chiude.
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('asks once when some episodes would not be imported',
        (tester) async {
      api.searchValue = season([
        testEpisodeChoice(1),
        testEpisodeChoice(2, wouldImport: false),
        testEpisodeChoice(3, wouldImport: false),
      ]);
      await open(tester);

      await tester.tap(grabAllButton('Scarica tutti (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Scaricare tutti gli episodi?'), findsOneWidget);
      expect(find.textContaining('2 episodi non verrebbero importati da Sonarr'),
          findsOneWidget);
      expect(find.textContaining('Radarr'), findsNothing);
      expect(grabs(), isEmpty);

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(grabs(), isEmpty);

      await tester.tap(grabAllButton('Scarica tutti (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Scarica').last);
      await tester.pumpAndSettle();
      expect(grabs(), hasLength(3));
      expect(find.text('Scaricare tutti gli episodi?'), findsNothing);
    });

    testWidgets('a row that would not import asks before grabbing',
        (tester) async {
      api.searchValue = season([testEpisodeChoice(1, wouldImport: false)]);
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Scarica').first);
      await tester.pumpAndSettle();

      expect(find.text(_confirmTitle), findsOneWidget);
      expect(find.textContaining('Sonarr non la importerebbe da solo'),
          findsOneWidget);
      expect(find.textContaining('Radarr'), findsNothing);
    });

    testWidgets('a row that does not improve its file asks, a better one not',
        (tester) async {
      api.searchValue = season([
        testEpisodeChoice(1, currentScore: 120),
        testEpisodeChoice(2, currentScore: 100),
        testEpisodeChoice(3, currentScore: 150),
      ]);
      await open(tester);

      // Punteggio pari (120 contro 120) e più basso (120 contro 150): chiede.
      for (final index in [0, 2]) {
        await tester
            .tap(find.widgetWithText(FilledButton, 'Scarica').at(index));
        await tester.pumpAndSettle();
        expect(find.text(_confirmTitle), findsOneWidget);
        expect(find.textContaining('non supera quello del file attuale'),
            findsOneWidget);
        await tester.tap(find.text('Annulla'));
        await tester.pumpAndSettle();
      }
      expect(grabs(), isEmpty);

      // Più alto e importabile: parte senza chiedere.
      await tester.tap(find.widgetWithText(FilledButton, 'Scarica').at(1));
      await tester.pumpAndSettle();
      expect(find.text(_confirmTitle), findsNothing);
      expect(grabs(), ['grab movie:1 e2 3']);
    });

    testWidgets('"Scarica tutti" asks when episodes do not improve',
        (tester) async {
      api.searchValue = season([
        testEpisodeChoice(1, currentScore: 120),
        testEpisodeChoice(2, currentScore: 150),
        testEpisodeChoice(3, currentScore: 100),
        testEpisodeChoice(4),
      ]);
      await open(tester);

      await tester.tap(grabAllButton('Scarica tutti (4)'));
      await tester.pumpAndSettle();
      expect(find.text('Scaricare tutti gli episodi?'), findsOneWidget);
      expect(find.textContaining('2 episodi non migliorano il file attuale'),
          findsOneWidget);
      expect(find.textContaining('non verrebbero importati'), findsNothing);
      expect(grabs(), isEmpty);
    });

    testWidgets('"Scarica tutti" does not ask when every episode improves',
        (tester) async {
      api.searchValue = season([
        testEpisodeChoice(1, currentScore: 100),
        testEpisodeChoice(2),
      ]);
      await open(tester);

      await tester.tap(grabAllButton('Scarica tutti (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Scaricare tutti gli episodi?'), findsNothing);
      expect(grabs(), hasLength(2));
    });

    testWidgets('wide layout has a column header above the box rows',
        (tester) async {
      api.searchValue = season([testEpisodeChoice(1)]);
      await open(tester);

      // Quella del riquadro e quella della lista completa.
      expect(find.text('Release'), findsNWidgets(2));
      expect(
          tester.getTopLeft(find.text('Release').first).dy,
          lessThan(tester.getTopLeft(find.text('E1')).dy));
    });

    testWidgets('narrow layout has no horizontal overflow', (tester) async {
      api.searchValue = season([
        testEpisodeChoice(1),
        testEpisodeChoice(2, hasRelease: false),
        testEpisodeChoice(12),
      ]);
      await open(tester, size: const Size(375, 800));

      expect(tester.takeException(), isNull);
      expect(find.text('Migliori episodi'), findsOneWidget);
      expect(find.text('nessun file valido'), findsOneWidget);
      expect(grabAllButton('Scarica tutti (2)'), findsOneWidget);
    });
  });

  group('background search', () {
    const jobs = SocialFeatures(
        inbox: true, downloads: true, downloadsSearchJobs: true, known: true);

    DownloadSearchStatus running(DateTime startedAt) => DownloadSearchStatus(
        key: 'movie:1',
        state: DownloadSearchJobState.running,
        startedAt: startedAt,
        service: 'Sonarr');

    final t0 = DateTime.utc(2026, 11, 1, 12);

    testWidgets('showsTheBarAndTheElapsedTime', (tester) async {
      var now = t0;
      await withClock(Clock(() => now), () async {
        api.searchStatuses.add(running(t0.subtract(const Duration(minutes: 2, seconds: 15))));
        await open(tester, settle: false, features: jobs);

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Ricerca su Sonarr in corso · 2:15'), findsOneWidget);
        expect(
            find.text(
                'Le stagioni anime possono richiedere qualche minuto: puoi chiudere, i risultati restano pronti.'),
            findsOneWidget);
        expect(find.text('Connessione persa, riprovo…'), findsNothing);

        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Ricerca su Sonarr in corso · 2:16'), findsOneWidget);
      });
    });

    testWidgets('aFutureStartedAtShowsZero', (tester) async {
      await withClock(Clock(() => t0), () async {
        api.searchStatuses.add(running(t0.add(const Duration(minutes: 5))));
        await open(tester, settle: false, features: jobs);

        expect(find.text('Ricerca su Sonarr in corso · 0:00'), findsOneWidget);
      });
    });

    DownloadSearchStatus waiting(int? typicalSeconds) => DownloadSearchStatus(
        key: 'movie:1',
        state: DownloadSearchJobState.running,
        startedAt: t0,
        service: 'Sonarr',
        waitingFor: DownloadSearchWaiting(
            title: 'One Piece · S22E40',
            since: t0.subtract(const Duration(minutes: 1, seconds: 20)),
            typicalSeconds: typicalSeconds));

    testWidgets('showsTheWaitingLineThenTheRunningOne', (tester) async {
      var now = t0;
      await withClock(Clock(() => now), () async {
        api.searchStatuses
          ..add(waiting(130))
          ..add(running(t0.add(const Duration(seconds: 3))));
        await open(tester, settle: false, features: jobs);

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
            find.text('In attesa: sta finendo una ricerca automatica '
                '(One Piece · S22E40, da 1:20, di solito ~2 min)'),
            findsOneWidget);
        expect(find.textContaining('Ricerca su'), findsNothing);

        now = now.add(DownloadSearchController.pollInterval);
        await tester.pump(DownloadSearchController.pollInterval);
        await tester.pump();
        expect(find.textContaining('In attesa'), findsNothing);
        expect(find.text('Ricerca su Sonarr in corso · 0:00'), findsOneWidget);
      });
    });

    testWidgets('theWaitingLineOmitsAnUnknownTypicalTime', (tester) async {
      await withClock(Clock(() => t0), () async {
        api.searchStatuses.add(waiting(null));
        await open(tester, settle: false, features: jobs);

        expect(
            find.text('In attesa: sta finendo una ricerca automatica '
                '(One Piece · S22E40, da 1:20)'),
            findsOneWidget);
      });
    });

    testWidgets('showsReconnecting', (tester) async {
      await withClock(Clock(() => t0), () async {
        api.searchStatuses
          ..add(running(t0))
          ..add(const DownloadsException(DownloadsFailure.network));
        await open(tester, settle: false, features: jobs);
        await tester.pump(DownloadSearchController.pollInterval);
        await tester.pump();

        expect(find.text('Connessione persa, riprovo…'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });
    });

    testWidgets('aPollingErrorOffersRetry', (tester) async {
      await withClock(Clock(() => t0), () async {
        api.searchStatuses
          ..add(running(t0))
          ..add(const DownloadsException(DownloadsFailure.network))
          ..add(const DownloadsException(DownloadsFailure.network))
          ..add(const DownloadsException(DownloadsFailure.network));
        await open(tester, settle: false, features: jobs);
        for (var i = 0; i < 3; i++) {
          await tester.pump(DownloadSearchController.pollInterval);
          await tester.pump();
        }
        expect(find.text('Riprova'), findsOneWidget);

        await tester.tap(find.text('Riprova'));
        await tester.pump();
        await tester.pump();

        expect(api.calls.where((c) => c.startsWith('start')),
            ['start movie:1', 'start movie:1']);
        expect(api.calls.any((c) => c.contains('again')), isFalse);
      });
    });

    testWidgets('without the feature the old waiting screen stays',
        (tester) async {
      api.searchGate = Completer<DownloadSearch>();
      await open(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('lighten', () {
    const atMinimum = 'Già al minimo';
    const isCurrent = 'È il file che hai già';
    const nothingLighter = 'Niente di più leggero con punteggio 120 o più';
    const why = 'Il più leggero tra quelli con punteggio 120 in 1080p';

    Finder inRow(String guid, Finder matching) => find.descendant(
        of: find.byKey(ValueKey('candidate-$guid')), matching: matching);

    test('the size limits are inclusive for the file, exclusive for lighter',
        () {
      final file = _search(current: _current120);
      expect(file.isCurrentFile(_row('a', 1020000000).release), isTrue);
      expect(file.isCurrentFile(_row('a', 980000000).release), isTrue);
      expect(file.isCurrentFile(_row('a', 1020000001).release), isFalse);
      expect(file.isCurrentFile(_row('a', 1000000000, score: 119).release),
          isFalse);
      expect(_search().isCurrentFile(_row('a', 1000000000).release), isFalse);

      bool lighter(DownloadCandidate c) =>
          _search(current: _current120, candidates: [c]).hasLighter;
      expect(lighter(_row('a', 900000000)), isFalse);
      expect(lighter(_row('a', 899999999)), isTrue);
      expect(lighter(_row('a', 899999999, score: 119)), isFalse);
      expect(lighter(_row('a', 899999999, score: 121)), isTrue);
      expect(_search(candidates: const []).hasLighter, isTrue);
    });

    testWidgets('the row equal to the file has no grab, the others do',
        (tester) async {
      api.searchValue = _search(current: _current120, candidates: [
        _row('g1', 1010000000),
        _row('heavier', 1030000000),
        _row('other', 1000000000, score: 100),
      ]);
      await open(tester, lighten: true);

      expect(inRow('g1', find.text(isCurrent)), findsOneWidget);
      expect(inRow('g1', find.byType(FilledButton)), findsNothing);
      // È la scelta della regola, ma niente oro né motivo.
      expect(find.text(why), findsNothing);
      final box = tester.widget<Container>(find
          .descendant(
              of: find.byKey(const ValueKey('candidate-g1')),
              matching: find.byType(Container))
          .first);
      expect((box.decoration! as BoxDecoration).color,
          isNot(const Color(0xFF2B2418)));
      for (final guid in ['heavier', 'other']) {
        expect(inRow(guid, find.text(isCurrent)), findsNothing);
        expect(inRow(guid, find.widgetWithText(FilledButton, 'Scarica')),
            findsOneWidget);
      }
    });

    testWidgets('narrow layout hides the grab too', (tester) async {
      api.searchValue =
          _search(current: _current120, candidates: [_row('g1', 1000000000)]);
      await open(tester, lighten: true, size: const Size(375, 800));

      expect(tester.takeException(), isNull);
      expect(find.text(isCurrent), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Scarica'), findsNothing);
    });

    testWidgets('warns when nothing is lighter', (tester) async {
      api.searchValue =
          _search(current: _current120, candidates: [_row('g1', 1000000000)]);
      await open(tester, lighten: true);

      expect(find.text(nothingLighter), findsOneWidget);
    });

    testWidgets('no warning with a lighter candidate of equal score',
        (tester) async {
      api.searchValue = _search(current: _current120, candidates: [
        _row('g1', 1000000000),
        _row('lighter', 800000000),
      ]);
      await open(tester, lighten: true);

      expect(find.text(nothingLighter), findsNothing);
      // Il pulsante c'è comunque: l'admin può scartare le alternative.
      expect(find.widgetWithText(OutlinedButton, atMinimum), findsOneWidget);
    });

    testWidgets('no warning with episode choices', (tester) async {
      api.searchValue = _search(
          current: _current120,
          candidates: [_row('g1', 1000000000)],
          episodeChoices: [testEpisodeChoice(1)]);
      await open(tester, lighten: true);

      expect(find.text(nothingLighter), findsNothing);
    });

    testWidgets('episodes without a release do not hide the warning',
        (tester) async {
      api.searchValue = _search(
          current: _current120,
          candidates: [_row('g1', 1000000000)],
          episodeChoices: [testEpisodeChoice(1, hasRelease: false)]);
      await open(tester, lighten: true);

      expect(find.text(nothingLighter), findsOneWidget);
    });

    testWidgets('without a current file: no button and no warning',
        (tester) async {
      await open(tester, lighten: true);

      expect(find.text(atMinimum), findsNothing);
      expect(find.textContaining('Niente di più leggero'), findsNothing);
    });

    testWidgets('the button marks the title and closes the page',
        (tester) async {
      api.searchValue = _search(current: _current120);
      await open(tester, lighten: true);

      await tester.tap(find.widgetWithText(OutlinedButton, atMinimum));
      await tester.pumpAndSettle();

      expect(space.calls, ['markAtMinimum movie:1 Film']);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('an error keeps the page and shows the message',
        (tester) async {
      api.searchValue = _search(current: _current120);
      space.nextActionFailure = SpaceFailure.unknown;
      await open(tester, lighten: true);

      await tester.tap(find.widgetWithText(OutlinedButton, atMinimum));
      await tester.pumpAndSettle();

      expect(find.text("Questo titolo non c'è più: ricalcola"), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('the button is off during a grab', (tester) async {
      api.searchValue = _search(current: _current120, candidates: [
        _row('g1', 1000000000),
        _row('other', 3000000000, score: 200),
      ]);
      await open(tester, lighten: true);
      api.actionGate = Completer<void>();

      await tester.tap(find.widgetWithText(FilledButton, 'Scarica'));
      await tester.pump();

      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, atMinimum))
              .onPressed,
          isNull);

      api.actionGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('without lighten the page does not change', (tester) async {
      api.searchValue =
          _search(current: _current120, candidates: [_row('g1', 1000000000)]);
      await open(tester);

      expect(find.text(atMinimum), findsNothing);
      expect(find.text(isCurrent), findsNothing);
      expect(find.text(nothingLighter), findsNothing);
      expect(inRow('g1', find.widgetWithText(FilledButton, 'Scarica')),
          findsOneWidget);
    });
  });

  testWidgets('an Arr error code shows its label and Riprova', (tester) async {
    api.searchValue = _search(error: 'Unreachable');
    await open(tester);

    expect(find.text("Non raggiungibile: controlla l'indirizzo"),
        findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
  });
}
