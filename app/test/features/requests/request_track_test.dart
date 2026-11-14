import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_labels.dart';
import 'package:wonderflix/features/requests/request_track.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/requests_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  final now = DateTime(2026, 10, 22, 12);
  setUpAll(() => initializeDateFormatting());

  MediaRequest request(RequestStatus status, {double? progress}) =>
      testMediaRequest(status: status, progress: progress);

  group('requestTrackModel', () {
    test('pending', () {
      final m = requestTrackModel(request(RequestStatus.pending), l)!;
      expect((m.current, m.half, m.fill), (1, false, 1));
      expect(m.labels[1], 'Da approvare');
      expect(m.labels, hasLength(4));
    });

    test('approved', () {
      final m = requestTrackModel(request(RequestStatus.approved), l)!;
      expect((m.current, m.fill), (2, 2));
      expect(m.labels[2], 'In arrivo');
    });

    test('awaitingRelease', () {
      final m = requestTrackModel(request(RequestStatus.awaitingRelease), l)!;
      expect((m.current, m.fill), (2, 2));
      expect(m.labels[2], 'Non ancora uscito');
    });

    test('downloading con e senza progresso', () {
      final withProgress = requestTrackModel(
        request(RequestStatus.downloading, progress: 0.42),
        l,
      )!;
      expect(withProgress.current, 2);
      expect(withProgress.fill, closeTo(2.42, 1e-9));
      expect(requestTrackModel(request(RequestStatus.downloading), l)!.fill, 2);
    });

    test('partial', () {
      final m = requestTrackModel(request(RequestStatus.partial), l)!;
      expect((m.current, m.half, m.fill), (3, true, 3));
      expect(m.labels[3], 'In parte');
    });

    test('stati non in corso: nessun percorso', () {
      for (final s in [
        RequestStatus.available,
        RequestStatus.declined,
        RequestStatus.failed,
        RequestStatus.removed,
        RequestStatus.notFound,
      ]) {
        expect(requestTrackModel(request(s), l), isNull, reason: '$s');
      }
    });
  });

  group('requestTrackDetail', () {
    List<(String, bool)> detail(MediaRequest r) => [
      for (final p in requestTrackDetail(r, now, l)) (p.text, p.upcoming),
    ];

    test('testi fissi', () {
      expect(detail(request(RequestStatus.pending)), [
        ("Aspetta l'ok di chi gestisce le richieste", false),
      ]);
      expect(detail(request(RequestStatus.approved)), [
        ('Approvata: si cerca una versione da scaricare', false),
      ]);
      expect(detail(request(RequestStatus.downloading, progress: 0.42)), [
        ('42% scaricato', false),
      ]);
      expect(detail(request(RequestStatus.downloading)), [
        ('Download in corso', false),
      ]);
    });

    test('partial senza prossimo episodio', () {
      expect(
        detail(
          testMediaRequest(
            status: RequestStatus.partial,
            type: RequestMediaType.tv,
          ),
        ),
        [('Una parte è già su WonderFlix', false)],
      );
    });

    test('partial con prossimo episodio futuro', () {
      final r = testMediaRequest(
        status: RequestStatus.partial,
        type: RequestMediaType.tv,
        nextAiring: DateTime(2026, 11, 3, 20),
        nextSeasonNumber: 2,
        nextEpisodeNumber: 4,
      );
      final expected = requestDateParts(r, now, l);
      expect(expected.single.upcoming, isTrue);
      expect(requestTrackDetail(r, now, l), expected);
    });

    test('awaitingRelease con le date del film', () {
      final r = testMediaRequest(
        status: RequestStatus.awaitingRelease,
        inCinemas: DateTime.utc(2026, 12, 4),
        digitalRelease: DateTime.utc(2027, 2, 1),
      );
      final expected = requestDateParts(r, now, l);
      expect(expected, isNotEmpty);
      expect(requestTrackDetail(r, now, l), expected);
    });

    test('stati chiusi: niente', () {
      expect(
        requestTrackDetail(request(RequestStatus.available), now, l),
        isEmpty,
      );
    });
  });

  group('RequestTrack', () {
    Future<void> pump(
      WidgetTester tester,
      MediaRequest r, {
      bool labels = true,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('it'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: RequestTrack(request: r, now: now, labels: labels),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final downloading = request(RequestStatus.downloading, progress: 0.42);

    testWidgets('con etichette si vedono le quattro tappe', (tester) async {
      await pump(tester, downloading);
      for (final s in ['Chiesta', 'Approvata', 'In arrivo', 'Su WonderFlix']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.textContaining('42%', findRichText: true), findsOneWidget);
    });

    testWidgets('senza etichette il dettaglio comincia dalla tappa attuale', (
      tester,
    ) async {
      await pump(tester, downloading, labels: false);
      expect(find.text('Chiesta'), findsNothing);
      expect(find.text('Su WonderFlix'), findsNothing);
      expect(
        find.text('In arrivo · 42% scaricato', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('senza etichette e senza dettaglio niente separatore', (
      tester,
    ) async {
      await pump(tester, request(RequestStatus.awaitingRelease), labels: false);
      expect(
        find.text('Non ancora uscito', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('una sola etichetta per lo screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, downloading);
      expect(
        find.bySemanticsLabel('Fatte: Chiesta, Approvata. Ora: In arrivo, 42%'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('stato non in corso: niente', (tester) async {
      await pump(tester, request(RequestStatus.available));
      expect(find.text('Chiesta'), findsNothing);
    });
  });
}
