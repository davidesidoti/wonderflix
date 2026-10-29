import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/features/downloads/download_search_page.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/download_fakes.dart';
import '../../support/pump_app.dart';

DownloadSearch _search({
  DownloadCurrentFile? current,
  List<DownloadCandidate>? candidates,
  List<DownloadRejected> rejected = const [],
  String? error,
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
    );

const _confirmTitle = 'Scaricare questa release?';
const _current120 =
    DownloadCurrentFile(sizeBytes: 1000000000, score: 120, quality: 'x');

void main() {
  late FakeDownloadsApi api;

  setUp(() => api = FakeDownloadsApi());

  /// Una pagina con un pulsante che apre la ricerca. Con [settle] falso si
  /// ferma durante l'attesa (lo spinner non si assesta mai).
  Future<void> open(
    WidgetTester tester, {
    bool reviewing = false,
    bool settle = true,
    Size size = const Size(1440, 900),
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDownloadSearch(context, 'movie:1', 'Film',
                reviewing: reviewing),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: adminTestOverrides(FakeAdminApi(),
          downloads: api,
          features: const SocialFeatures(inbox: true, downloads: true)),
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
  ]) {
    testWidgets('BusyAndArrDownShowAMessage ${failure.name}', (tester) async {
      api.nextActionFailure = failure;
      await open(tester);

      await tapGrab(tester);

      expect(find.text(text), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
    });
  }

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

  testWidgets('an Arr error code shows its label and Riprova', (tester) async {
    api.searchValue = _search(error: 'Unreachable');
    await open(tester);

    expect(find.text("Non raggiungibile: controlla l'indirizzo"),
        findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
  });
}
