import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/reports/reports_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/reports/admin_reports_controller.dart';
import 'package:wonderflix/features/reports/reports_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/admin_fakes.dart' show testAdmin;
import '../../support/fake_session_controller.dart';
import '../../support/report_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeReportsApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeReportsApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container({bool admin = true, bool reports = true}) {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        reportsApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            SessionSignedIn(admin ? testAdmin : testUser))),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            SocialFeatures(reports: reports, known: true))),
      ],
    );
    c.listen(adminReportsProvider, (_, _) {});
    return c;
  }

  test("un non admin non chiama l'API", () async {
    api.reports.add(testReport());
    final c = container(admin: false);
    expect(await c.read(adminReportsProvider.future), isEmpty);
    expect(api.calls, isEmpty);
  });

  test("senza la funzione reports non chiama l'API", () async {
    api.reports.add(testReport());
    final c = container(reports: false);
    expect(await c.read(adminReportsProvider.future), isEmpty);
    expect(api.calls, isEmpty);
  });

  test('InboxChanged ricarica', () async {
    final c = container();
    expect(await c.read(adminReportsProvider.future), isEmpty);
    api.reports.add(testReport());
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(adminReportsProvider).value, hasLength(1));
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, ['all', 'all', 'all']);
  });

  test('resolve chiama e ricarica', () async {
    api.reports.add(testReport());
    final c = container();
    final report = (await c.read(adminReportsProvider.future)).single;
    await c
        .read(adminReportsProvider.notifier)
        .resolve(report, ReportOutcome.fixed, note: 'ok');
    expect(api.calls, ['all', 'resolve r1 Fixed ok', 'all']);
    expect(c.read(adminReportsProvider).value, isEmpty);
  });

  test('chiusa da un altro admin: messaggio e ricarica', () async {
    api.reports.add(testReport());
    final c = container();
    final report = (await c.read(adminReportsProvider.future)).single;
    // L'altro admin l'ha già chiusa.
    api.reports.clear();
    api.nextFailure = ReportsFailure.closed;
    await expectLater(
      c
          .read(adminReportsProvider.notifier)
          .resolve(report, ReportOutcome.cannotFix),
      throwsA(isA<ReportsException>()
          .having((e) => e.failure, 'failure', ReportsFailure.closed)),
    );
    expect(api.calls.last, 'all');
    expect(c.read(adminReportsProvider).value, isEmpty);
  });

  test('un altro errore non ricarica', () async {
    api.reports.add(testReport());
    final c = container();
    final report = (await c.read(adminReportsProvider.future)).single;
    api.nextFailure = ReportsFailure.network;
    await expectLater(
        c
            .read(adminReportsProvider.notifier)
            .resolve(report, ReportOutcome.fixed),
        throwsA(isA<ReportsException>()));
    expect(api.calls, ['all', 'resolve r1 Fixed -']);
    expect(c.read(adminReportsProvider).value, hasLength(1));
  });

  group('reportShortcut', () {
    test('sottotitoli di un film o di un episodio', () {
      expect(reportShortcut(testReport(itemType: ReportItemType.episode)),
          ReportShortcut.subtitles);
      expect(reportShortcut(testReport(itemType: ReportItemType.movie)),
          ReportShortcut.subtitles);
    });

    test('altrimenti nessuna', () {
      expect(
          reportShortcut(testReport(itemType: ReportItemType.series)), isNull);
      expect(
          reportShortcut(testReport(itemType: ReportItemType.season)), isNull);
      expect(reportShortcut(testReport(itemType: null)), isNull);
      expect(reportShortcut(testReport(type: ReportType.metadata)), isNull);
    });
  });
}
