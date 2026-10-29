import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/features/downloads/download_rows.dart';
import 'package:wonderflix/features/downloads/downloads_tab.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/download_fakes.dart';
import '../../support/pump_app.dart';

DownloadChoice _choice(
  String key, {
  Duration age = const Duration(days: 1),
  int? previousScore,
  bool byAdmin = false,
}) =>
    DownloadChoice(
      key: key,
      kind: DownloadKind.movie,
      title: 'Scelto $key',
      at: DateTime.now().subtract(age),
      release: testRelease(guid: key),
      previousScore: previousScore,
      byAdmin: byAdmin,
    );

DownloadItem _item(
  String key, {
  DownloadState state = DownloadState.waiting,
  DownloadReason? reason,
}) =>
    DownloadItem(
      key: key,
      kind: DownloadKind.movie,
      title: 'Voce $key',
      state: state,
      reason: reason,
      availableSince: DateTime.now().subtract(const Duration(days: 3)),
    );

ReviewItem _review(int n) => ReviewItem(
      key: 'movie:$n',
      kind: DownloadKind.movie,
      title: 'Da ripassare $n',
      score: 90,
      sizeBytes: 2000000000,
      quality: 'WEBRip-720p',
    );

void main() {
  late FakeDownloadsApi api;
  late SharedPreferences prefs;

  setUp(() async {
    api = FakeDownloadsApi();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: DownloadsTab()),
        overrides: [
          ...adminTestOverrides(FakeAdminApi(),
              downloads: api,
              features: const SocialFeatures(inbox: true, downloads: true)),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        surfaceSize: const Size(1440, 20000));
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('le sezioni sono nell\'ordine', (tester) async {
    api.overviewValue = DownloadsOverview(
      enabled: true,
      recent: [_choice('movie:1')],
      waiting: [
        _item('movie:2'),
        _item('movie:3', state: DownloadState.needsYou),
      ],
      review: [_review(4)],
    );
    await pumpTab(tester);

    final titles = [
      'Serve te · 1',
      'Scelte automatiche · 1',
      'In attesa · 1',
      'Da ripassare · 1',
    ];
    for (var i = 1; i < titles.length; i++) {
      expect(y(tester, titles[i]), greaterThan(y(tester, titles[i - 1])));
    }
  });

  testWidgets('Serve te sparisce se è vuota', (tester) async {
    api.overviewValue =
        DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
    await pumpTab(tester);

    expect(find.textContaining('Serve te'), findsNothing);
    expect(find.text('In attesa · 1'), findsOneWidget);
  });

  testWidgets('7 giorni, poi tutte con Mostra altre', (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true, recent: [
      _choice('movie:1'),
      _choice('movie:2', age: const Duration(days: 20)),
    ]);
    await pumpTab(tester);

    expect(find.text('Scelto movie:1'), findsOneWidget);
    expect(find.text('Scelto movie:2'), findsNothing);

    await tester.tap(find.text('Mostra altre'));
    await tester.pumpAndSettle();
    expect(find.text('Scelto movie:2'), findsOneWidget);
    expect(find.text('Mostra altre'), findsNothing);
  });

  testWidgets('Da ripassare: 50 alla volta', (tester) async {
    api.overviewValue = DownloadsOverview(
        enabled: true, review: [for (var i = 0; i < 120; i++) _review(i)]);
    await pumpTab(tester);

    expect(find.byType(ReviewRow), findsNWidgets(50));
    await tester.tap(find.text('Mostra altre'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewRow), findsNWidgets(100));
    await tester.tap(find.text('Mostra altre'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewRow), findsNWidgets(120));
    expect(find.text('Mostra altre'), findsNothing);
  });

  testWidgets('con la funzione spenta c\'è la nota', (tester) async {
    api.overviewValue = const DownloadsOverview(enabled: false);
    await pumpTab(tester);

    expect(
        find.text('Download automatici spenti: WonderFlix non scarica da '
            'solo. Ricerca e Da ripassare funzionano.'),
        findsOneWidget);
  });

  testWidgets('l\'errore di un servizio si vede', (tester) async {
    api.overviewValue = const DownloadsOverview(
        enabled: true, sonarrError: 'Unreachable', radarrError: 'Unauthorized');
    await pumpTab(tester);

    expect(find.textContaining('Sonarr: Non raggiungibile'), findsOneWidget);
    expect(find.text('Radarr: Chiave API rifiutata'), findsOneWidget);
  });

  testWidgets('un upgrade mostra prima e dopo', (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true, recent: [
      _choice('movie:1', previousScore: 90, byAdmin: true),
    ]);
    await pumpTab(tester);

    expect(find.text('upgrade 90 → 120'), findsOneWidget);
    expect(find.text('scelta tua'), findsOneWidget);
  });

  testWidgets('una voce in attesa mostra il suo motivo', (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true, waiting: [
      _item('movie:2', reason: DownloadReason.searchFailed),
    ]);
    await pumpTab(tester);

    expect(find.textContaining('ricerca non riuscita'), findsOneWidget);
  });

  testWidgets('Cerca ora chiama il plugin e rilegge', (tester) async {
    api.overviewValue =
        DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
    await pumpTab(tester);
    api.calls.clear();

    await tester.tap(find.text('Cerca ora'));
    await tester.pumpAndSettle();

    expect(api.calls, ['searchNow movie:2', 'overview']);
  });

  testWidgets('Cerca ora che fallisce dice il motivo e non logga',
      (tester) async {
    api.overviewValue =
        DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
    await pumpTab(tester);
    api.nextActionFailure = DownloadsFailure.invalid;
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    await tester.tap(find.text('Cerca ora'));
    await tester.pumpAndSettle();

    expect(find.text('Richiesta non valida'), findsOneWidget);
    expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
  });

  testWidgets('un errore di caricamento ha il suo testo', (tester) async {
    api.overviewError = const DownloadsException(DownloadsFailure.forbidden);
    await pumpTab(tester);

    expect(find.text(lookupAppLocalizations(const Locale('it')).errorAccountDisabled),
        findsOneWidget);
  });

  testWidgets('Guarda apre la ricerca e alla chiusura rilegge',
      (tester) async {
    api.overviewValue =
        DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
    await pumpTab(tester);
    api.calls.clear();

    await tester.tap(find.text('Guarda'));
    await tester.pumpAndSettle();
    expect(find.text('Voce movie:2'), findsWidgets);
    expect(api.calls, ['search movie:2']);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(api.calls, ['search movie:2', 'overview']);
  });

  group('sezioni compattabili', () {
    const key = 'downloads.collapsedSections';

    void fill() => api.overviewValue = DownloadsOverview(
          enabled: true,
          recent: [_choice('movie:1')],
          waiting: [
            _item('movie:2'),
            _item('movie:3', state: DownloadState.needsYou),
          ],
          review: [_review(4)],
        );

    testWidgets('un tocco sull intestazione nasconde le voci, il secondo le '
        'rimostra', (tester) async {
      fill();
      await pumpTab(tester);
      expect(find.text('Scelto movie:1'), findsOneWidget);

      await tester.tap(find.text('Scelte automatiche · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Scelto movie:1'), findsNothing);
      expect(find.text('Scelte automatiche · 1'), findsOneWidget);
      expect(find.text('Voce movie:2'), findsOneWidget);
      expect(prefs.getStringList(key), ['chosen']);

      await tester.tap(find.text('Scelte automatiche · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Scelto movie:1'), findsOneWidget);
      expect(prefs.getStringList(key), isEmpty);
    });

    testWidgets('chiusa nasconde anche Mostra altre e aggiornato',
        (tester) async {
      api.overviewValue = DownloadsOverview(
        enabled: true,
        reviewAt: DateTime.now(),
        review: [for (var i = 0; i < 60; i++) _review(i)],
      );
      await pumpTab(tester);
      expect(find.text('Mostra altre'), findsOneWidget);
      expect(find.textContaining('aggiornato'), findsOneWidget);

      await tester.tap(find.text('Da ripassare · 60'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewRow), findsNothing);
      expect(find.text('Mostra altre'), findsNothing);
      expect(find.textContaining('aggiornato'), findsNothing);
    });

    testWidgets('resta chiusa quando la scheda si rimonta, le altre no',
        (tester) async {
      fill();
      await pumpTab(tester);
      await tester.tap(find.text('In attesa · 1'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await pumpTab(tester);

      expect(find.text('In attesa · 1'), findsOneWidget);
      expect(find.text('Voce movie:2'), findsNothing);
      expect(find.text('Scelto movie:1'), findsOneWidget);
      expect(find.text('Voce movie:3'), findsOneWidget);
      expect(find.byType(ReviewRow), findsOneWidget);
    });

    testWidgets('legge le sezioni chiuse dalle preferenze', (tester) async {
      SharedPreferences.setMockInitialValues({
        key: ['needsYou', 'review', 'sconosciuta'],
      });
      prefs = await SharedPreferences.getInstance();
      fill();
      await pumpTab(tester);

      expect(find.text('Voce movie:3'), findsNothing);
      expect(find.byType(ReviewRow), findsNothing);
      expect(find.text('Scelto movie:1'), findsOneWidget);
      expect(find.text('Voce movie:2'), findsOneWidget);
    });

    testWidgets('l intestazione è un pulsante che dice se è aperta',
        (tester) async {
      fill();
      final handle = tester.ensureSemantics();
      await pumpTab(tester);

      Matcher header(bool expanded) => isSemantics(
          isButton: true, hasExpandedState: true, isExpanded: expanded);
      expect(tester.getSemantics(find.text('In attesa · 1')), header(true));
      await tester.tap(find.text('In attesa · 1'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.text('In attesa · 1')), header(false));
      handle.dispose();
    });
  });
}
