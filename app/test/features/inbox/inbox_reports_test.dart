import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

final _at = DateTime.utc(2026, 10, 21, 20);

ReportPendingEntry _pending({
  String? titleId = 's1',
  String itemId = 'ep1',
  ReportItemType? itemType = ReportItemType.episode,
  String title = 'Dark',
  int? season = 2,
  int? episode = 3,
  String? text,
}) =>
    ReportPendingEntry(
      id: 'p1',
      seq: 1,
      createdAt: _at,
      read: false,
      reportId: 'rep1',
      reportType: ReportType.subtitles,
      fromName: 'Luigi',
      itemId: itemId,
      itemType: itemType,
      titleId: titleId,
      title: title,
      seasonNumber: season,
      episodeNumber: episode,
      text: text,
    );

ReportResolvedEntry _resolved({
  ReportOutcome outcome = ReportOutcome.fixed,
  String? titleId = 's1',
  ReportItemType? itemType = ReportItemType.episode,
  String title = 'Dark',
  String? text,
}) =>
    ReportResolvedEntry(
      id: 'q1',
      seq: 2,
      createdAt: _at,
      read: false,
      reportId: 'rep1',
      reportType: ReportType.subtitles,
      outcome: outcome,
      itemId: 'ep1',
      itemType: itemType,
      titleId: titleId,
      title: title,
      text: text,
    );

void main() {
  /// Il pannello con le voci date, in un router che ha anche `/item/:id`: la
  /// scheda scrive id e stagione richiesti.
  Future<ProviderContainer> pumpPanel(
      WidgetTester tester, List<InboxEntry> entries) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: entries, unread: 1);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
            ),
          ),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (context, state) => Text(
              'scheda ${state.pathParameters['id']} '
              '${state.uri.queryParameters['season']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const SizedBox.shrink()),
        ...socialTestOverrides(api,
            features: const SocialFeatures(inbox: true)),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    return container;
  }

  testWidgets(
      'la voce pending mostra chi, titolo, livello e tipo, e apre la serie',
      (tester) async {
    final container = await pumpPanel(tester, [_pending()]);

    expect(find.text('Luigi ha segnalato un problema'), findsOneWidget);
    expect(find.text('Dark · S2 E3 · Sottotitoli'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inbox-report-p1')));
    await tester.pumpAndSettle();

    // Un episodio apre la serie, senza stagione (decisione 4).
    expect(find.text('scheda s1 null'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('la voce di una stagione apre la serie su quella stagione',
      (tester) async {
    await pumpPanel(tester, [
      _pending(
          itemId: 'se2',
          itemType: ReportItemType.season,
          season: 2,
          episode: null),
    ]);

    await tester.tap(find.byKey(const Key('inbox-report-p1')));
    await tester.pumpAndSettle();

    expect(find.text('scheda s1 se2'), findsOneWidget);
  });

  testWidgets('la voce resolved mostra l\'esito e la nota tra virgolette',
      (tester) async {
    await pumpPanel(tester, [_resolved(text: 'sincronizzati')]);

    expect(find.text('Problema sistemato su Dark'), findsOneWidget);
    expect(find.text('«sincronizzati»'), findsOneWidget);
  });

  testWidgets('la voce resolved CannotFix dice che non si è potuto',
      (tester) async {
    await pumpPanel(
        tester, [_resolved(outcome: ReportOutcome.cannotFix)]);

    expect(find.text('Non è stato possibile sistemare Dark'), findsOneWidget);
    expect(find.textContaining('«'), findsNothing);
  });

  testWidgets('titolo sparito: testo con "un titolo" e nessuna navigazione',
      (tester) async {
    final container = await pumpPanel(tester, [
      _resolved(titleId: null, itemType: null, title: ''),
    ]);

    expect(find.text('Problema sistemato su un titolo'), findsOneWidget);
    expect(find.byType(WfImage), findsNothing);

    await tester.tap(find.byKey(const Key('inbox-report-q1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('scheda'), findsNothing);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });
}
