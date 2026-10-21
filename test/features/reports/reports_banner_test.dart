import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/reports/reports_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/reports/reports_banner.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';
import '../../support/settings_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeReportsApi api;
  late FakeSessionController session;
  late ValueNotifier<bool> shown;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeReportsApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    events = StreamController<ServerEvent>.broadcast();
    shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    addTearDown(events.close);
  });

  Future<void> pumpBanner(
    WidgetTester tester, {
    String titleId = 's1',
    bool admin = true,
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder(
          valueListenable: shown,
          builder: (_, visible, _) => visible
              ? SingleChildScrollView(child: ReportsBanner(titleId: titleId))
              : const SizedBox.shrink(),
        ),
      ),
      overrides: [
        ...adminTestOverrides(
          FakeAdminApi(),
          session: admin
              ? session
              : FakeSessionController(const SessionSignedIn(testUser)),
          features: const SocialFeatures(reports: true, known: true),
        ),
        ...reportTestOverrides(reports: api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        libraryApiProvider.overrideWithValue(
          FakeLibraryApi()..mediaInfoById['e1'] = testMediaInfo(),
        ),
        userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      ],
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.text(label);

  testWidgets('solo le segnalazioni di quel titolo, con livello e nota', (
    tester,
  ) async {
    api.reports.addAll([
      testReport(id: 'r1', note: 'Fuori sincrono', userName: 'Luigi'),
      testReport(
        id: 'r2',
        itemId: 's1',
        itemType: ReportItemType.series,
        seasonNumber: null,
        episodeNumber: null,
        type: ReportType.metadata,
        userName: 'Anna',
      ),
      testReport(id: 'r3', titleId: 's2', userName: 'Carlo'),
    ]);
    await pumpBanner(tester);

    expect(find.text(it.reportsBannerTitle(2)), findsOneWidget);
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('S1 E2 · Sottotitoli'), findsOneWidget);
    expect(find.text('Fuori sincrono'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Tutta la serie · Titolo o informazioni'), findsOneWidget);
    expect(find.text(it.reportNoNote), findsOneWidget);
    expect(find.text('Carlo'), findsNothing);
  });

  testWidgets('niente per chi non è admin', (tester) async {
    api.reports.add(testReport());
    await pumpBanner(tester, admin: false);
    expect(find.byType(Text), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('niente senza segnalazioni di quel titolo', (tester) async {
    api.reports.add(testReport());
    await pumpBanner(tester, titleId: 'altro');
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('Sistemato con la nota chiama resolve(fixed, nota)', (
    tester,
  ) async {
    api.reports.add(testReport());
    await pumpBanner(tester);

    await tester.tap(button(it.reportFixed));
    await tester.pumpAndSettle();
    expect(find.text(it.reportResolveFixedTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Sottotitoli aggiornati ');
    await tester.tap(button(it.reportResolveConfirm));
    await tester.pumpAndSettle();

    expect(api.calls, [
      'all',
      'resolve r1 Fixed Sottotitoli aggiornati',
      'all',
    ]);
    expect(find.text(it.reportResolveFixedTitle), findsNothing);
    expect(find.text('Luigi'), findsNothing);
  });

  testWidgets('Non sistemabile senza nota', (tester) async {
    api.reports.add(testReport());
    await pumpBanner(tester);

    await tester.tap(button(it.reportCannotFix));
    await tester.pumpAndSettle();
    expect(find.text(it.reportResolveCannotFixTitle), findsOneWidget);
    await tester.tap(button(it.reportResolveConfirm));
    await tester.pumpAndSettle();

    expect(api.calls, ['all', 'resolve r1 CannotFix -', 'all']);
  });

  testWidgets(
    'chiusa da un altro admin: snackbar e riquadro senza quella voce',
    (tester) async {
      api.reports.addAll([
        testReport(id: 'r1', userName: 'Luigi'),
        testReport(id: 'r2', userName: 'Anna'),
      ]);
      await pumpBanner(tester);
      // L'altro admin ha chiuso la prima mentre il riquadro era aperto.
      api.reports.removeWhere((report) => report.id == 'r1');
      api.nextFailure = ReportsFailure.closed;

      await tester.tap(button(it.reportFixed).first);
      await tester.pumpAndSettle();
      await tester.tap(button(it.reportResolveConfirm));
      await tester.pumpAndSettle();

      expect(find.text(it.reportAlreadyClosed), findsOneWidget);
      expect(find.text(it.reportResolveFixedTitle), findsNothing);
      expect(find.text('Luigi'), findsNothing);
      expect(find.text('Anna'), findsOneWidget);
      expect(find.text(it.reportsBannerTitle(1)), findsOneWidget);
    },
  );

  testWidgets('un altro errore resta nella finestra', (tester) async {
    api.reports.add(testReport());
    await pumpBanner(tester);
    api.nextFailure = ReportsFailure.network;

    await tester.tap(button(it.reportFixed));
    await tester.pumpAndSettle();
    await tester.tap(button(it.reportResolveConfirm));
    await tester.pumpAndSettle();

    expect(find.text(it.reportResolveFixedTitle), findsOneWidget);
    expect(find.text('Luigi'), findsOneWidget);
  });

  testWidgets(
    'scorciatoia solo per i sottotitoli di un film o di un episodio',
    (tester) async {
      api.reports.addAll([
        testReport(id: 'r1', itemType: ReportItemType.episode),
        testReport(id: 'r2', itemType: ReportItemType.movie),
        testReport(
          id: 'r3',
          itemType: ReportItemType.series,
          seasonNumber: null,
        ),
        testReport(id: 'r4', type: ReportType.audioVideo),
        testReport(id: 'r5', itemType: null),
      ]);
      await pumpBanner(tester);
      expect(button(it.reportShortcutSubtitles), findsNWidgets(2));

      await tester.tap(button(it.reportShortcutSubtitles).first);
      await tester.pumpAndSettle();
      expect(find.text(it.subtitlesDialogTitle), findsWidgets);
    },
  );

  group('la voce sparisce mentre la finestra è aperta', () {
    /// Apre la finestra su r1, poi un altro admin la chiude e `InboxChanged`
    /// ricarica, e la scheda (con il riquadro) si smonta: la finestra resta
    /// aperta senza nessun altro che tenga vivo il provider.
    Future<void> openThenVanish(WidgetTester tester) async {
      api.reports.add(testReport());
      await pumpBanner(tester);
      await tester.tap(button(it.reportFixed));
      await tester.pumpAndSettle();
      api.reports.clear();
      events.add(inboxChangedReceived());
      shown.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Luigi'), findsNothing, reason: 'riquadro tolto');
      expect(find.text(it.reportResolveFixedTitle), findsOneWidget);
    }

    testWidgets('Conferma chiama resolve una volta e chiude', (tester) async {
      await openThenVanish(tester);
      await tester.tap(button(it.reportResolveConfirm));
      await tester.pumpAndSettle();

      // Il provider è rimasto vivo: la finestra l'ha tenuto vivo, nessun notifier nuovo.
      expect(api.calls, ['all', 'all', 'resolve r1 Fixed -', 'all']);
      expect(find.text(it.reportResolveFixedTitle), findsNothing);
      expect(find.text(it.reportAlreadyClosed), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('già chiusa: la finestra si chiude con lo snackbar', (
      tester,
    ) async {
      await openThenVanish(tester);
      api.nextFailure = ReportsFailure.closed;
      await tester.tap(button(it.reportResolveConfirm));
      await tester.pumpAndSettle();

      expect(
        api.calls.where((call) => call.startsWith('resolve')),
        hasLength(1),
      );
      expect(find.text(it.reportResolveFixedTitle), findsNothing);
      expect(find.text(it.reportAlreadyClosed), findsOneWidget);
    });
  });

  testWidgets('403: messaggio nella finestra e utente riletto', (tester) async {
    api.reports.add(testReport());
    await pumpBanner(tester);
    api.nextFailure = ReportsFailure.forbidden;

    await tester.tap(button(it.reportFixed));
    await tester.pumpAndSettle();
    await tester.tap(button(it.reportResolveConfirm));
    await tester.pumpAndSettle();

    expect(find.text(it.reportNoPermission), findsOneWidget);
    expect(find.text(it.reportResolveFixedTitle), findsOneWidget);
    expect(session.refreshUserCalls, 1);
  });
}
