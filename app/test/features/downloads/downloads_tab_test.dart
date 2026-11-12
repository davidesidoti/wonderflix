import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/admin/admin_action_button.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/downloads/download_rows.dart';
import 'package:wonderflix/features/downloads/downloads_tab.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/tv_focusable.dart';

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
  List<DownloadAction> actions = const [],
  String? blockedMessage,
  bool snoozed = false,
  DownloadProgress? progress,
  DownloadSearchPhase? searchPhase,
  String? externalSearchUrl,
  String? title,
  int? seriesId,
  bool canRush = false,
  bool rush = false,
}) =>
    DownloadItem(
      key: key,
      kind: DownloadKind.movie,
      title: title ?? 'Voce $key',
      state: state,
      reason: reason,
      availableSince: DateTime.now().subtract(const Duration(days: 3)),
      actions: actions,
      blockedMessage: blockedMessage,
      snoozed: snoozed,
      progress: progress,
      searchPhase: searchPhase,
      externalSearchUrl: externalSearchUrl,
      seriesId: seriesId,
      canRush: canRush,
      rush: rush,
    );

ReviewItem _review(int n, {bool canHunt = true}) => ReviewItem(
      key: 'movie:$n',
      kind: DownloadKind.movie,
      title: 'Da ripassare $n',
      score: 90,
      sizeBytes: 2000000000,
      quality: 'WEBRip-720p',
      canHunt: canHunt,
    );

void main() {
  late FakeDownloadsApi api;
  late SharedPreferences prefs;

  setUp(() async {
    api = FakeDownloadsApi();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// [settle] falso con una barra indeterminata: anima per sempre.
  Future<void> pumpTab(WidgetTester tester,
      {bool settle = true, bool tv = false}) async {
    await pumpApp(tester, const Scaffold(body: DownloadsTab()),
        overrides: [
          ...adminTestOverrides(FakeAdminApi(),
              downloads: api,
              features: const SocialFeatures(inbox: true, downloads: true)),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        surfaceSize: const Size(1440, 20000),
        tv: tv);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
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

  group('Senza titolo', () {
    const pack = UnknownDownload(
      service: 'Sonarr',
      downloadId: 'D1',
      title: 'Outlander 2015 S01',
      sizeBytes: 27000000000,
      message: 'Series title mismatch',
    );

    testWidgets('sta sotto Serve te, senza contarci, e dice tutto',
        (tester) async {
      api.overviewValue = DownloadsOverview(
        enabled: true,
        waiting: [_item('movie:3', state: DownloadState.needsYou)],
        unknown: const [pack],
      );
      await pumpTab(tester);

      expect(y(tester, 'Senza titolo · 1'), greaterThan(y(tester, 'Serve te · 1')));
      expect(y(tester, 'Scelte automatiche · 0'), greaterThan(y(tester, 'Senza titolo · 1')));
      expect(find.text('Outlander 2015 S01'), findsOneWidget);
      expect(find.text('Sonarr'), findsOneWidget);
      expect(find.text('27,00 GB'), findsOneWidget);
      expect(find.text('Series title mismatch'), findsOneWidget);
    });

    testWidgets('non c\'è se è vuota', (tester) async {
      await pumpTab(tester);

      expect(find.textContaining('Senza titolo'), findsNothing);
    });

    testWidgets('si chiude come le altre', (tester) async {
      api.overviewValue = const DownloadsOverview(enabled: true, unknown: [pack]);
      await pumpTab(tester);

      await tester.tap(find.text('Senza titolo · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Outlander 2015 S01'), findsNothing);
    });

    testWidgets('Rimuovi chiede conferma: annullando non chiama il plugin',
        (tester) async {
      api.overviewValue = const DownloadsOverview(enabled: true, unknown: [pack]);
      await pumpTab(tester);
      api.calls.clear();

      await tester.tap(find.text('Rimuovi'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Outlander 2015 S01 (27,00 GB): torrent e file vengono cancellati per sempre.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(api.calls, isEmpty);
    });

    testWidgets('confermando toglie il download e rilegge', (tester) async {
      api.overviewValue = const DownloadsOverview(enabled: true, unknown: [pack]);
      await pumpTab(tester);
      api.calls.clear();

      await tester.tap(find.text('Rimuovi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi').last);
      await tester.pumpAndSettle();

      expect(api.calls, ['removeUnknown Sonarr D1', 'overview']);
      expect(find.text('Fatto'), findsOneWidget);
    });
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

  group('coda delle ricerche', () {
    testWidgets('senza Progress non c\'è', (tester) async {
      api.overviewValue = const DownloadsOverview(enabled: true);
      await pumpTab(tester);

      expect(find.text('ricerche automatiche'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('in cima, con conteggio, barra, fine stimata e ritmo',
        (tester) async {
      api.overviewValue = DownloadsOverview(
        enabled: true,
        waiting: [_item('movie:2')],
        progress: SearchProgress(
          done: 140,
          remaining: 460,
          perHour: 32.4,
          estimatedEnd: DateTime.now().add(const Duration(hours: 2)),
        ),
      );
      await pumpTab(tester);

      expect(find.text('140 / 600'), findsOneWidget);
      expect(find.text('ricerche automatiche'), findsOneWidget);
      expect(find.textContaining('Fine stimata'), findsOneWidget);
      expect(find.textContaining('(~2 h)'), findsOneWidget);
      expect(find.text('~32 ricerche/ora'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(140 / 600, 1e-9));
      expect(y(tester, '140 / 600'), lessThan(y(tester, 'In attesa · 1')));
    });

    testWidgets('in pausa: niente stima', (tester) async {
      api.overviewValue = DownloadsOverview(
        enabled: false,
        progress: SearchProgress(
          done: 1,
          remaining: 2,
          estimatedEnd: DateTime.now().add(const Duration(hours: 2)),
          paused: true,
        ),
      );
      await pumpTab(tester);

      expect(find.text('In pausa'), findsOneWidget);
      expect(find.textContaining('Fine stimata'), findsNothing);
      expect(find.textContaining('ricerche/ora'), findsNothing);
    });

    testWidgets('ricerca manuale: in pausa con il motivo', (tester) async {
      api.overviewValue = const DownloadsOverview(
        enabled: true,
        progress: SearchProgress(done: 1, remaining: 2, manualSearch: true),
      );
      await pumpTab(tester);

      expect(find.text('In pausa: ricerca manuale in corso'), findsOneWidget);
      expect(find.text('Stima in calcolo…'), findsNothing);
    });

    testWidgets('senza fine stimata: in calcolo', (tester) async {
      api.overviewValue = const DownloadsOverview(
        enabled: true,
        progress: SearchProgress(done: 0, remaining: 5),
      );
      await pumpTab(tester);

      expect(find.text('0 / 5'), findsOneWidget);
      expect(find.text('Stima in calcolo…'), findsOneWidget);
    });

    testWidgets('su TV c\'è uguale', (tester) async {
      api.overviewValue = const DownloadsOverview(
        enabled: true,
        progress: SearchProgress(done: 3, remaining: 7, perHour: 1),
      );
      await pumpTab(tester, tv: true);

      expect(find.text('3 / 10'), findsOneWidget);
      expect(find.text('~1 ricerca/ora'), findsOneWidget);
    });
  });

  group('cabina', () {
    LampState lamp(WidgetTester tester) =>
        tester.widget<WfLamp>(find.byType(WfLamp)).state;

    testWidgets('il titolo della scheda è in cima', (tester) async {
      api.overviewValue = const DownloadsOverview(enabled: true);
      await pumpTab(tester);

      expect(find.byType(AdminTabTitle), findsOneWidget);
    });

    Future<void> lampIs(WidgetTester tester, DownloadsOverview overview,
        LampState expected) async {
      api.overviewValue = overview;
      await pumpTab(tester);
      expect(lamp(tester), expected);
    }

    testWidgets('la spia è verde se la coda corre', (tester) async {
      await lampIs(
          tester,
          const DownloadsOverview(
              enabled: true, progress: SearchProgress(done: 1, remaining: 2)),
          LampState.ok);
    });

    testWidgets('la spia è gialla in pausa',
        (tester) async {
      await lampIs(
          tester,
          const DownloadsOverview(
              enabled: true,
              progress: SearchProgress(done: 1, remaining: 2, paused: true)),
          LampState.attention);
    });

    testWidgets('la spia è gialla per la ricerca manuale', (tester) async {
      await lampIs(
          tester,
          const DownloadsOverview(
              enabled: true,
              progress:
                  SearchProgress(done: 1, remaining: 2, manualSearch: true)),
          LampState.attention);
    });

    testWidgets('la spia è rossa se Sonarr o Radarr non rispondono',
        (tester) async {
      await lampIs(
          tester,
          const DownloadsOverview(
              enabled: true,
              radarrError: 'Unreachable',
              progress: SearchProgress(done: 1, remaining: 2)),
          LampState.broken);
    });

    testWidgets('Serve te: la riga ha il bordo oro', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:5',
            state: DownloadState.needsYou,
            reason: DownloadReason.belowMinScore,
            actions: [DownloadAction.pick])
      ]);
      await pumpTab(tester);

      final shell = tester.widget<RowShell>(find.descendant(
          of: find.byKey(const ValueKey('item-movie:5')),
          matching: find.byType(RowShell)));
      expect(shell.accent, WfColors.gold);
      expect(shell.leftAccent, isTrue);
    });
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

  testWidgets('In attesa: prima ciò che è in corso, il resto nel suo ordine',
      (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true, waiting: [
      _item('movie:1'),
      _item('movie:2', searchPhase: DownloadSearchPhase.queued),
      _item('movie:3', state: DownloadState.upgradeWatch),
      _item('movie:4', searchPhase: DownloadSearchPhase.searching),
      _item('movie:5', state: DownloadState.downloading),
    ]);
    await pumpTab(tester, settle: false);

    final order = ['movie:5', 'movie:4', 'movie:2', 'movie:1', 'movie:3'];
    for (var i = 1; i < order.length; i++) {
      expect(y(tester, 'Voce ${order[i]}'),
          greaterThan(y(tester, 'Voce ${order[i - 1]}')));
    }
  });

  testWidgets('Aggiorna rilegge i download', (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true);
    await pumpTab(tester);
    api.calls.clear();

    await tester.tap(find.text('Aggiorna'));
    await tester.pumpAndSettle();

    expect(api.calls, ['overview']);
  });

  testWidgets('Cerca ora chiama il plugin e rilegge', (tester) async {
    api.overviewValue =
        DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
    await pumpTab(tester);
    api.calls.clear();

    await tester.tap(find.text('Cerca ora'));
    await tester.pumpAndSettle();

    expect(api.calls, ['searchNow movie:2', 'overview']);
    expect(find.text('Ricerca avviata'), findsOneWidget);
  });

  testWidgets('Cerca un upgrade chiama il plugin e rilegge', (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true, review: [_review(4)]);
    await pumpTab(tester);
    api.calls.clear();

    await tester.tap(find.text('Cerca un upgrade'));
    await tester.pumpAndSettle();

    expect(api.calls, ['hunt movie:4', 'overview']);
    expect(find.text('Ricerca avviata'), findsOneWidget);
  });

  testWidgets('Cerca un upgrade su un titolo cambiato lo dice e rilegge',
      (tester) async {
    api.overviewValue = DownloadsOverview(enabled: true, review: [_review(4)]);
    await pumpTab(tester);
    api.calls.clear();
    api.nextActionFailure = DownloadsFailure.changed;

    await tester.tap(find.text('Cerca un upgrade'));
    await tester.pumpAndSettle();

    expect(api.calls, ['hunt movie:4', 'overview']);
    expect(find.text('È cambiato qualcosa nel frattempo: ricarico'),
        findsOneWidget);
  });

  testWidgets("Cerca un upgrade non c'è se non può partire", (tester) async {
    api.overviewValue = DownloadsOverview(
        enabled: true, review: [_review(4, canHunt: false), _review(5)]);
    await pumpTab(tester);
    expect(find.text('Cerca un upgrade'), findsOneWidget);
    expect(find.text('Apri'), findsNWidgets(2));
  });

  testWidgets("Cerca un upgrade non c'è con i download spenti",
      (tester) async {
    api.overviewValue =
        DownloadsOverview(enabled: false, review: [_review(4), _review(5)]);
    await pumpTab(tester);
    expect(find.text('Apri'), findsNWidgets(2));
    expect(find.text('Cerca un upgrade'), findsNothing);
  });

  group('fasi della ricerca', () {
    LinearProgressIndicator bar(WidgetTester tester) =>
        tester.widget(find.byType(LinearProgressIndicator));

    testWidgets('in coda: il testo e la barra indeterminata', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:2', searchPhase: DownloadSearchPhase.queued),
      ]);
      await pumpTab(tester, settle: false);

      expect(find.textContaining('In coda per la ricerca…'), findsOneWidget);
      expect(bar(tester).value, isNull);
    });

    testWidgets('in ricerca: il testo e la barra indeterminata',
        (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:3',
            state: DownloadState.needsYou,
            searchPhase: DownloadSearchPhase.searching),
      ]);
      await pumpTab(tester, settle: false);

      expect(find.textContaining('Cerco tra gli indexer…'), findsOneWidget);
      expect(bar(tester).value, isNull);
    });

    testWidgets('senza fase: niente barra', (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
      await pumpTab(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('con una fase si rilegge ogni 5 secondi, senza ogni 60',
        (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:2', searchPhase: DownloadSearchPhase.searching),
      ]);
      await pumpTab(tester, settle: false);

      // La prima lettura del poller parte subito; il conto riparte da lì.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      api.calls.clear();

      await tester.pump(const Duration(seconds: 4));
      expect(api.calls, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.calls, ['overview']);

      // La ricerca è finita: la lettura dopo non ha più fasi.
      api.overviewValue =
          DownloadsOverview(enabled: true, waiting: [_item('movie:2')]);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(api.calls, ['overview', 'overview']);

      await tester.pump(const Duration(seconds: 55));
      expect(api.calls.length, 2);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(api.calls.length, 3);
    });
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

    testWidgets('un valore di altro tipo nelle preferenze: tutte aperte',
        (tester) async {
      SharedPreferences.setMockInitialValues({key: 'chosen'});
      prefs = await SharedPreferences.getInstance();
      fill();
      await pumpTab(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Scelto movie:1'), findsOneWidget);
      expect(find.text('Voce movie:2'), findsOneWidget);
      expect(find.text('Voce movie:3'), findsOneWidget);
      expect(find.byType(ReviewRow), findsOneWidget);
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

  group('Avanzamento', () {
    testWidgets('un download in corso mostra barra e riga', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:2',
            state: DownloadState.downloading,
            progress: DownloadProgress(
              sizeBytes: 3100000000,
              sizeLeftBytes: 1178000000,
              estimatedCompletion:
                  DateTime.now().add(const Duration(minutes: 25, seconds: 30)),
              status: 'downloading',
            )),
        _item('movie:3'),
      ]);
      await pumpTab(tester);

      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.62, 0.001));
      expect(find.textContaining('62% · 1,92 GB di 3,10 GB · finisce tra '),
          findsOneWidget);
    });

    testWidgets('fermo sui metadati: riga con la durata, niente barra, Scarta',
        (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:2',
            state: DownloadState.downloading,
            actions: [
              DownloadAction.pick,
              DownloadAction.searchNow,
              DownloadAction.discard
            ],
            progress: DownloadProgress(
              sizeBytes: 0,
              sizeLeftBytes: 0,
              status: 'metadata',
              since: clock.now().subtract(const Duration(hours: 3)),
            )),
      ]);
      await pumpTab(tester);

      expect(find.textContaining('Recupero i metadati da 3 h'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Scarta e cerca un altro'), findsOneWidget);

      api.calls.clear();
      await tester.tap(find.text('Scarta e cerca un altro'));
      await tester.pumpAndSettle();
      expect(api.calls, ['discard movie:2', 'overview']);
    });

    testWidgets('una voce in attesa non ha la barra', (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: true, waiting: [_item('movie:3')]);
      await pumpTab(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('Serve te', () {
    DownloadItem needs(DownloadReason reason, List<DownloadAction> actions,
            {String? blockedMessage}) =>
        _item('movie:5',
            state: DownloadState.needsYou,
            reason: reason,
            actions: actions,
            blockedMessage: blockedMessage);

    void fill(DownloadItem item) =>
        api.overviewValue = DownloadsOverview(enabled: true, waiting: [item]);

    Finder button(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

    testWidgets('i pulsanti nell ordine, il primo in evidenza',
        (tester) async {
      fill(needs(DownloadReason.belowMinScore, [
        DownloadAction.grabBest,
        DownloadAction.pick,
        DownloadAction.searchNow,
      ]));
      await pumpTab(tester);

      final labels = ['Scarica il migliore intanto', 'Scegli tu', 'Cerca ora'];
      expect(
          tester
              .widgetList<AdminActionButton>(find.byType(AdminActionButton))
              .map((b) => b.label)
              .where((label) => label != 'Aggiorna'),
          labels);
      expect(tester.widget(button(labels[0])), isA<FilledButton>());
      expect(tester.widget(button(labels[1])), isA<OutlinedButton>());
      expect(tester.widget(button(labels[2])), isA<OutlinedButton>());
      expect(find.text('Guarda'), findsNothing);
    });

    testWidgets('Scarica il migliore chiama il plugin e rilegge',
        (tester) async {
      fill(needs(DownloadReason.belowMinScore,
          [DownloadAction.grabBest, DownloadAction.pick]));
      await pumpTab(tester);
      api.calls.clear();
      api.actionGate = Completer<void>();

      await tester.tap(find.text('Scarica il migliore intanto'));
      await tester.pump();
      expect(find.text('Cerco e scarico…'), findsOneWidget);

      api.actionGate!.complete();
      await tester.pumpAndSettle();
      expect(api.calls, ['grabBest movie:5', 'overview']);
      expect(find.text('Fatto'), findsOneWidget);
    });

    testWidgets('niente da prendere: avviso e rilettura', (tester) async {
      fill(needs(DownloadReason.belowMinScore, [DownloadAction.grabBest]));
      await pumpTab(tester);
      api.calls.clear();
      api.nextActionFailure = DownloadsFailure.nothingToGrab;

      await tester.tap(find.text('Scarica il migliore intanto'));
      await tester.pumpAndSettle();

      expect(find.text("Non c'è più niente da scaricare: ricarico"),
          findsOneWidget);
      expect(api.calls, ['grabBest movie:5', 'overview']);
    });

    testWidgets('import bloccato: messaggio, Importa e Scarta', (tester) async {
      fill(needs(DownloadReason.importBlocked,
          [DownloadAction.import, DownloadAction.discard],
          blockedMessage: 'Not an upgrade for existing movie file'));
      await pumpTab(tester);

      expect(find.text('Not an upgrade for existing movie file'),
          findsOneWidget);
      expect(find.textContaining('Radarr non lo importa'), findsOneWidget);
      expect(tester.widget(button('Importa comunque')), isA<FilledButton>());
      expect(find.text('Scarta e cerca un altro'), findsOneWidget);
      expect(find.text('Cerca ora'), findsNothing);

      api.calls.clear();
      await tester.tap(find.text('Scarta e cerca un altro'));
      await tester.pumpAndSettle();
      expect(api.calls, ['discard movie:5', 'overview']);
    });

    testWidgets('client che rifiuta: Scegli un altro file', (tester) async {
      fill(needs(DownloadReason.grabRefused,
          [DownloadAction.pick, DownloadAction.searchNow]));
      await pumpTab(tester);

      expect(find.text('Scegli un altro file'), findsOneWidget);
      api.calls.clear();
      await tester.tap(find.text('Scegli un altro file'));
      await tester.pumpAndSettle();
      expect(api.calls, ['search movie:5']);
    });

    testWidgets('in attesa senza avvisi: l etichetta', (tester) async {
      fill(_item('movie:6',
          snoozed: true,
          actions: [DownloadAction.pick, DownloadAction.searchNow]));
      await pumpTab(tester);

      expect(find.text('senza avvisi'), findsOneWidget);
      expect(find.text('Guarda'), findsOneWidget);
      expect(tester.widget(button('Guarda')), isA<OutlinedButton>());
    });

    testWidgets('Cerca su MIRCrew: il pulsante apre il browser, non il plugin',
        (tester) async {
      fill(_item('movie:5',
          state: DownloadState.needsYou,
          reason: DownloadReason.nothingFound,
          actions: [DownloadAction.searchNow, DownloadAction.externalSearch],
          externalSearchUrl: 'https://mircrew.example/search?q=Film'));
      await pumpTab(tester);

      expect(tester.widget(button('Cerca su MIRCrew')), isA<OutlinedButton>());
      api.calls.clear();
      await tester.tap(find.text('Cerca su MIRCrew'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
    });

    testWidgets('plugin vecchio: i pulsanti di prima', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:2'),
        _item('movie:3',
            state: DownloadState.needsYou, reason: DownloadReason.nothingFound),
      ]);
      await pumpTab(tester);

      expect(find.text('Guarda'), findsNWidgets(2));
      expect(find.text('Cerca ora'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('cerca nella lista', () {
    const field = ValueKey('downloads-filter');

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(field), text);
      await tester.pump();
    }

    List<DownloadItem> episodes({bool rush = false}) => [
          _item('episode:1',
              title: 'Serie · S01E01', seriesId: 7, canRush: true, rush: rush),
          _item('episode:2',
              title: 'Serie · S01E02', seriesId: 7, canRush: true, rush: rush),
        ];

    testWidgets('il filtro restringe ogni sezione e nasconde le vuote',
        (tester) async {
      api.overviewValue = DownloadsOverview(
        enabled: true,
        recent: [_choice('movie:1')],
        waiting: [
          _item('movie:2', title: 'Alpha'),
          _item('movie:3', title: 'Beta'),
        ],
        review: [_review(4)],
      );
      await pumpTab(tester);

      await type(tester, 'alpha');

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      expect(find.text('In attesa · 1'), findsOneWidget);
      expect(find.textContaining('Da ripassare'), findsNothing);
      expect(find.textContaining('Scelte automatiche'), findsNothing);
    });

    testWidgets('il filtro apre le sezioni chiuse senza salvarle',
        (tester) async {
      const key = 'downloads.collapsedSections';
      SharedPreferences.setMockInitialValues({
        key: ['waiting', 'review'],
      });
      prefs = await SharedPreferences.getInstance();
      api.overviewValue = DownloadsOverview(
        enabled: true,
        waiting: [_item('movie:2', title: 'Alpha')],
        review: [_review(4)],
      );
      await pumpTab(tester);
      expect(find.byType(ReviewRow), findsNothing);

      await type(tester, 'a');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.byType(ReviewRow), findsOneWidget);
      await tester.tap(find.text('In attesa · 1'));
      await tester.pumpAndSettle();

      expect(prefs.getStringList(key), ['waiting', 'review']);
    });

    testWidgets('il filtro ignora i 7 giorni e la paginazione', (tester) async {
      api.overviewValue = DownloadsOverview(
        enabled: true,
        recent: [_choice('movie:9', age: const Duration(days: 30))],
        review: [for (var i = 0; i < 60; i++) _review(i)],
      );
      await pumpTab(tester);
      expect(find.text('Scelto movie:9'), findsNothing);

      await type(tester, 'movie:9');
      expect(find.text('Scelto movie:9'), findsOneWidget);

      await type(tester, 'ripassare 55');
      expect(find.text('Da ripassare 55'), findsOneWidget);
      expect(find.text('Mostra altre'), findsNothing);
    });

    testWidgets('il ricaricamento non tocca il testo né il focus',
        (tester) async {
      api.overviewValue = DownloadsOverview(
          enabled: true, waiting: [_item('movie:2', title: 'Alpha')]);
      await pumpTab(tester);
      await tester.tap(find.byKey(field));
      await type(tester, 'alp');
      api.calls.clear();

      await tester.pump(const Duration(seconds: 60));
      await tester.pump();

      expect(api.calls, ['overview']);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, 'alp');
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('il campo si svuota con la X', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: [
        _item('movie:2', title: 'Alpha'),
        _item('movie:3', title: 'Beta'),
      ]);
      await pumpTab(tester);
      expect(find.byIcon(LucideIcons.x), findsNothing);

      await type(tester, 'alpha');
      expect(find.text('Beta'), findsNothing);
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('Scarica subito chiama rush e rilegge', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: episodes());
      await pumpTab(tester);
      await type(tester, 'serie');
      api.calls.clear();

      expect(find.text('2 mancanti'), findsOneWidget);
      await tester.tap(find.text('Scarica subito'));
      await tester.pumpAndSettle();

      expect(api.calls, ['rush episode:1', 'overview']);
    });

    testWidgets('senza testo nel campo non ci sono righe Scarica subito',
        (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true, waiting: episodes());
      await pumpTab(tester);

      expect(find.text('Scarica subito'), findsNothing);
      expect(find.byType(DownloadRushRow), findsNothing);
    });

    testWidgets('niente pulsante con i download spenti', (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: false, waiting: episodes());
      await pumpTab(tester);

      await type(tester, 'serie');

      expect(find.text('2 mancanti'), findsOneWidget);
      expect(find.text('Scarica subito'), findsNothing);
    });

    testWidgets('con tutte le righe davanti si legge In testa alla coda',
        (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: true, waiting: episodes(rush: true));
      await pumpTab(tester);

      await type(tester, 'serie');

      expect(find.text('In testa alla coda'), findsOneWidget);
      expect(find.text('Scarica subito'), findsNothing);
    });

    testWidgets('con i download spenti non si legge In testa alla coda',
        (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: false, waiting: episodes(rush: true));
      await pumpTab(tester);

      await type(tester, 'serie');

      expect(find.text('2 mancanti'), findsOneWidget);
      expect(find.text('In testa alla coda'), findsNothing);
      expect(find.text('Scarica subito'), findsNothing);
    });

    testWidgets('Non è in lista compare anche con righe vecchie trovate',
        (tester) async {
      api.overviewValue = DownloadsOverview(
          enabled: true, recent: [_choice('movie:1')], refreshPending: false);
      await pumpTab(tester);

      await type(tester, 'Scelto');

      expect(find.text('Scelto movie:1'), findsOneWidget);
      expect(find.text('Non è in lista'), findsOneWidget);
      expect(find.text('Aggiorna ora'), findsOneWidget);
    });

    testWidgets('Non è in lista non compare se una riga in attesa corrisponde',
        (tester) async {
      api.overviewValue = DownloadsOverview(
          enabled: true,
          waiting: [_item('movie:2', title: 'Alpha')],
          refreshPending: false);
      await pumpTab(tester);

      await type(tester, 'alpha');

      expect(find.text('Non è in lista'), findsNothing);
    });

    testWidgets('Aggiorna ora chiama refresh', (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: true, refreshPending: false);
      await pumpTab(tester);
      await type(tester, 'dune');
      api.calls.clear();

      await tester.tap(find.text('Aggiorna ora'));
      await tester.pumpAndSettle();

      expect(api.calls, ['refresh', 'overview']);
    });

    testWidgets(
        'con RefreshPending si legge Aggiornamento e si rilegge ogni 5 secondi',
        (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: true, refreshPending: true);
      await pumpTab(tester, settle: false);
      await type(tester, 'dune');

      expect(find.text('Non è in lista'), findsOneWidget);
      expect(find.text('Aggiornamento…'), findsOneWidget);
      expect(find.text('Aggiorna ora'), findsNothing);

      // La prima lettura del poller parte subito; il conto riparte da lì.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      api.calls.clear();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(api.calls, ['overview']);
    });

    testWidgets('con un plugin vecchio niente Aggiorna ora', (tester) async {
      api.overviewValue = DownloadsOverview(enabled: true);
      await pumpTab(tester);

      await type(tester, 'dune');

      expect(find.text('Non è in lista'), findsNothing);
      expect(find.text('Aggiorna ora'), findsNothing);
    });

    testWidgets('con i download spenti niente Aggiorna ora', (tester) async {
      api.overviewValue =
          DownloadsOverview(enabled: false, refreshPending: false);
      await pumpTab(tester);

      await type(tester, 'dune');

      expect(find.text('Aggiorna ora'), findsNothing);
    });

    testWidgets('su TV il campo è una tappa del telecomando', (tester) async {
      api.overviewValue = DownloadsOverview(
          enabled: true, waiting: [_item('movie:2', title: 'Alpha')]);
      await pumpTab(tester, tv: true);
      EditableText editable() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(
          find.ancestor(
              of: find.byKey(field), matching: find.byType(TvFocusable)),
          findsOneWidget);
      bool onField() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<TvFocusable>() !=
          null;

      // Aggiorna, poi il campo: raggiunto, non attivo.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(onField(), isTrue);
      expect(editable().focusNode.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(onField(), isFalse);
      expect(editable().focusNode.hasFocus, isFalse);
    });
  });
}
