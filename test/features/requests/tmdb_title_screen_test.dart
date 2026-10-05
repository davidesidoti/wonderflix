import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/tmdb_title_screen.dart';
import 'package:wonderflix/ui/backdrop_image.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;

  setUp(() => api = FakeRequestsApi());

  Future<void> pumpScreen(WidgetTester tester,
      {RequestMediaType type = RequestMediaType.movie, int tmdbId = 693134}) async {
    await pumpApp(
      tester,
      Scaffold(body: TmdbTitleScreen(type: type, tmdbId: tmdbId)),
      overrides: requestsTestOverrides(api),
    );
    await tester.pump();
    await tester.pump();
  }

  test('scheda da una rotta', () {
    expect(TmdbTitleScreen.fromRoute('movie', '693134')!.tmdbId, 693134);
    expect(TmdbTitleScreen.fromRoute('tv', '90228')!.type, RequestMediaType.tv);
    expect(TmdbTitleScreen.fromRoute('person', '1'), isNull);
    expect(TmdbTitleScreen.fromRoute('movie', 'abc'), isNull);
    expect(TmdbTitleScreen.fromRoute('movie', '0'), isNull);
  });

  testWidgets('film: dati, trailer e Richiedi con l\'avviso', (tester) async {
    api.titles[693134] =
        testDetails(trailerUrl: 'https://www.youtube.com/watch?v=x');
    await pumpScreen(tester);

    expect(find.text('DUNE - PARTE DUE'), findsOneWidget);
    expect(find.text('2024 · Film · 2h 46m'), findsOneWidget);
    expect(find.text('Fantascienza · Avventura'), findsOneWidget);
    expect(find.text('Paul Atreides si unisce ai Fremen.'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Guarda'), findsNothing);

    await tester.tap(find.text('Richiedi'));
    await tester.pump();
    await tester.pump();

    expect(api.created.single.type, RequestMediaType.movie);
    expect(find.text('Richiesta inviata'), findsOneWidget);
  });

  testWidgets('serie: stagioni e Richiedi con le stagioni scelte', (tester) async {
    api.titles[90228] = testDetails(
      tmdbId: 90228,
      title: 'Dune: Prophecy',
      type: RequestMediaType.tv,
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 6),
        SeasonInfo(seasonNumber: 2, episodeCount: 8),
      ],
    );
    await pumpScreen(tester, type: RequestMediaType.tv, tmdbId: 90228);

    expect(find.text('2024 · Serie · 2 stagioni'), findsOneWidget);
    expect(find.text('Stagioni'), findsOneWidget);
    expect(find.text('Richiedi'), findsOneWidget);

    await tester.tap(find.text('Stagione 2 · 8 episodi'));
    await tester.pump();
    expect(find.text('Richiedi 1 stagione'), findsOneWidget);

    await tester.tap(find.text('Richiedi 1 stagione'));
    await tester.pump();
    await tester.pump();

    expect(api.created.single.seasons, [1]);
  });

  testWidgets('già chiesto da te: l\'etichetta al posto di Richiedi', (tester) async {
    api.titles[693134] = testDetails(
        status: TitleStatus.pending, requestedByMe: true, requested: true);
    await pumpScreen(tester);

    expect(find.text('Richiesto da te'), findsOneWidget);
    expect(find.text('Richiedi'), findsNothing);
  });

  testWidgets('in parte nella libreria: Richiedi e Guarda', (tester) async {
    api.titles[90228] = testDetails(
      tmdbId: 90228,
      type: RequestMediaType.tv,
      status: TitleStatus.partial,
      jellyfinItemId: 'abc',
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 6, status: TitleStatus.available),
        SeasonInfo(seasonNumber: 2, episodeCount: 8),
      ],
    );
    await pumpScreen(tester, type: RequestMediaType.tv, tmdbId: 90228);

    expect(find.text('Richiedi'), findsOneWidget);
    expect(find.text('Guarda'), findsOneWidget);
    expect(find.text('Tutte'), findsNothing);
  });

  testWidgets('chi non può chiedere vede solo i dati', (tester) async {
    api
      ..meValue = const RequestsMe(canRequest: false, canManage: false, hasAccount: true)
      ..titles[693134] = testDetails();
    await pumpScreen(tester);

    expect(find.text('Richiedi'), findsNothing);
    expect(api.calls, contains('me'));
  });

  testWidgets('i permessi si caricano con la scheda: scheletro finché non arrivano',
      (tester) async {
    final gate = api.meGate = Completer<void>();
    api.titles[693134] = testDetails();
    await pumpScreen(tester);

    // La scheda è pronta, ma i permessi no: ancora lo scheletro.
    expect(api.calls, containsAll(['me', 'title:movie:693134']));
    expect(find.byType(DetailSkeleton), findsOneWidget);
    expect(find.text('DUNE - PARTE DUE'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();

    // Al primo fotogramma con i dati c'è già Richiedi.
    expect(find.text('DUNE - PARTE DUE'), findsOneWidget);
    expect(find.text('Richiedi'), findsOneWidget);
  });

  testWidgets('permessi che falliscono: la scheda resta, senza Richiedi',
      (tester) async {
    api
      ..meFailure = RequestsFailure.seerrUnavailable
      ..titles[693134] = testDetails();
    await pumpScreen(tester);
    // Finita la dissolvenza dallo scheletro.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('DUNE - PARTE DUE'), findsOneWidget);
    expect(find.text('Richiedi'), findsNothing);
    expect(find.byType(DetailSkeleton), findsNothing);
  });

  testWidgets('lo sfondo scorre con la testata, con la rotella dolce',
      (tester) async {
    api.titles[90228] = testDetails(
      tmdbId: 90228,
      type: RequestMediaType.tv,
      seasons: [
        for (var n = 1; n <= 20; n++) SeasonInfo(seasonNumber: n, episodeCount: 8),
      ],
    );
    await pumpScreen(tester, type: RequestMediaType.tv, tmdbId: 90228);
    // Finita la dissolvenza dallo scheletro.
    await tester.pump(const Duration(seconds: 1));
    final backdrop = find.byType(BackdropImage);
    expect(tester.getTopLeft(backdrop).dy, 0);
    expect(tester.widget<ListView>(find.byType(ListView)).controller,
        isA<SmoothScrollController>());

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    // Sale insieme alle sfumature della testata: non resta fermo dietro.
    expect(tester.getTopLeft(backdrop).dy, -300);
  });

  testWidgets('Seerr giù: errore e Riprova', (tester) async {
    api.failure = RequestsFailure.seerrUnavailable;
    await pumpScreen(tester);

    expect(find.text('Seerr non risponde'), findsOneWidget);

    api
      ..failure = null
      ..titles[693134] = testDetails();
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('DUNE - PARTE DUE'), findsOneWidget);
  });
}
