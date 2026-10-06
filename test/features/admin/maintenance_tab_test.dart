import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/features/admin/maintenance_tab.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeAdminApi api;

  setUp(() {
    api = FakeAdminApi()
      ..librariesValue = testLibraries()
      ..tasksValue = testTasks();
  });

  /// Alta abbastanza per tutte le righe.
  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: MaintenanceTab()),
        overrides: adminTestOverrides(api),
        surfaceSize: const Size(1440, 2400));
    await tester.pumpAndSettle();
  }

  Finder inRow(String rowKey, Finder matching) =>
      find.descendant(of: find.byKey(ValueKey(rowKey)), matching: matching);

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<OutlinedButton>(button).onPressed != null;

  testWidgets('librerie: scansione in corso e Scansiona', (tester) async {
    await pumpTab(tester);

    expect(find.text('Librerie'), findsOneWidget);
    for (final name in ['Movies', 'Collezioni2', 'Anime', 'Shows']) {
      expect(find.text(name), findsOneWidget);
    }
    const movies = 'library-f137a2dd21bbc1b99aa5c0f6bf02a805';
    const shows = 'library-a656b907eb3a73532e40e44b968d0225';
    expect(
        find.byKey(const Key(
            'library-progress-f137a2dd21bbc1b99aa5c0f6bf02a805')),
        findsOneWidget);
    expect(enabled(tester, inRow(movies, find.bySubtype<OutlinedButton>())),
        isFalse);
    expect(enabled(tester, inRow(shows, find.bySubtype<OutlinedButton>())),
        isTrue);

    await tester.tap(inRow(shows, find.text('Scansiona')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('scan:a656b907eb3a73532e40e44b968d0225'));

    // "Scansiona tutte", con l'ultima scansione accanto.
    expect(find.byKey(const Key('scan-all-status')), findsOneWidget);
    await tester.tap(find.text('Scansiona tutte'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('start:t-scan'));
  });

  group('"Scansiona tutte"', () {
    /// Il fixture con "Scansione della libreria" nello stato [state].
    List<ScheduledTask> withScanTask(TaskState state, {double? progress}) => [
          for (final task in testTasks())
            if (task.key == ScheduledTask.refreshLibraryKey)
              ScheduledTask(
                id: task.id,
                name: task.name,
                key: task.key,
                category: task.category,
                state: state,
                progress: progress,
              )
            else
              task,
        ];

    bool scanAllEnabled(WidgetTester tester) => enabled(
        tester,
        find.ancestor(
            of: find.text('Scansiona tutte'),
            matching: find.bySubtype<OutlinedButton>()));

    String? statusText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('scan-all-status'))).data;

    testWidgets('ferma: attiva, con l\'ultima scansione accanto', (tester) async {
      await pumpTab(tester);

      expect(scanAllEnabled(tester), isTrue);
      expect(statusText(tester), startsWith('Ultima: '));
    });

    testWidgets('scansione in corso: spenta, con la percentuale', (tester) async {
      api.tasksValue = withScanTask(TaskState.running, progress: 12.4);
      await pumpTab(tester);

      expect(scanAllEnabled(tester), isFalse);
      expect(statusText(tester), '12%');
    });

    testWidgets('scansione in arresto: spenta, con "Arresto…"', (tester) async {
      api.tasksValue = withScanTask(TaskState.cancelling, progress: 80);
      await pumpTab(tester);

      expect(scanAllEnabled(tester), isFalse);
      expect(statusText(tester), 'Arresto…');
    });

    testWidgets('senza l\'attività della scansione: spenta', (tester) async {
      api.tasksValue = [
        for (final task in testTasks())
          if (task.key != ScheduledTask.refreshLibraryKey) task,
      ];
      await pumpTab(tester);

      expect(scanAllEnabled(tester), isFalse);
      expect(find.byKey(const Key('scan-all-status')), findsNothing);
    });
  });

  testWidgets('attività: gruppi in ordine e stati', (tester) async {
    await pumpTab(tester);

    expect(find.text('Attività pianificate'), findsOneWidget);
    final applicazione = tester.getTopLeft(find.text('Applicazione')).dy;
    final introSkipper = tester.getTopLeft(find.text('Intro Skipper')).dy;
    final trakt = tester.getTopLeft(find.text('Trakt')).dy;
    expect(applicazione, lessThan(introSkipper));
    expect(introSkipper, lessThan(trakt));

    expect(inRow('task-t-autocol', find.text('38%')), findsOneWidget);
    expect(inRow('task-t-autocol', find.text('Ferma')), findsOneWidget);
    expect(inRow('task-t-webhook', find.text('Arresto…')), findsOneWidget);
    expect(inRow('task-t-webhook', find.bySubtype<OutlinedButton>()),
        findsNothing);
    expect(inRow('task-t-skipme', find.text('Mai eseguita')), findsOneWidget);
    expect(inRow('task-t-keyframe', find.textContaining('Annullata')),
        findsOneWidget);
    expect(
        inRow('task-t-optimize', find.textContaining('Completata in 3 min')),
        findsOneWidget);
    expect(inRow('task-t-optimize', find.text('Avvia')), findsOneWidget);
  });

  testWidgets('"Non riuscita" apre il messaggio d\'errore', (tester) async {
    await pumpTab(tester);

    expect(find.textContaining('401 (Unauthorized)'), findsNothing);
    await tester.tap(inRow('task-t-trakt', find.text('Non riuscita')));
    await tester.pump();
    expect(find.textContaining('401 (Unauthorized)'), findsOneWidget);
  });

  testWidgets('Avvia e Ferma chiamano Jellyfin', (tester) async {
    await pumpTab(tester);

    await tester.tap(inRow('task-t-optimize', find.text('Avvia')));
    await tester.pumpAndSettle();
    await tester.tap(inRow('task-t-autocol', find.text('Ferma')));
    await tester.pumpAndSettle();

    expect(api.calls, containsAllInOrder(['start:t-optimize', 'stop:t-autocol']));
  });

  testWidgets('azione rifiutata: un avviso', (tester) async {
    api.actionError = const ServerErrorException(500);
    await pumpTab(tester);

    await tester.tap(inRow('task-t-optimize', find.text('Avvia')));
    await tester.pumpAndSettle();

    expect(find.text(it.errorGeneric), findsOneWidget);
  });

  testWidgets('senza dati: errore e Riprova', (tester) async {
    api.librariesError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);
    api.librariesError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsOneWidget);
  });
}
