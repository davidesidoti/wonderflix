import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_groups.dart';

import '../../support/social_fakes.dart';

void main() {
  final t = DateTime.utc(2026, 11, 16);

  // Tutti i 20 tipi: 10 in Server, 10 in Per te (constraints della fase 5).
  final server = <InboxEntry>[
    DownloadNeedsYouEntry(
      id: 'a',
      seq: 1,
      createdAt: t,
      read: false,
      title: 'Dune',
    ),
    DownloadStalledEntry(
      id: 'b',
      seq: 1,
      createdAt: t,
      read: false,
      title: 'Dune',
    ),
    LightenBlockedEntry(
      id: 'c',
      seq: 1,
      createdAt: t,
      read: false,
      title: 'Dune',
    ),
    SpaceOperationFailedEntry(id: 'd', seq: 1, createdAt: t, read: false),
    DiskAlmostFullEntry(
      id: 'e',
      seq: 1,
      createdAt: t,
      read: false,
      percent: 95,
    ),
    RestartPendingEntry(id: 'f', seq: 1, createdAt: t, read: false),
    RecoveryStartedEntry(id: 'g', seq: 1, createdAt: t, read: false),
    RecoveryBlockedEntry(id: 'h', seq: 1, createdAt: t, read: false),
    testRequestPending(),
    ReportPendingEntry(
      id: 'p',
      seq: 1,
      createdAt: t,
      read: false,
      reportId: 'r',
      fromName: 'Garg',
      itemId: 'm1',
      title: 'Dune',
    ),
  ];
  final forYou = <InboxEntry>[
    testInvite(),
    testMatchInviteEntry(),
    testRecommendationEntry(),
    testAnnouncement(),
    testNewTitles(),
    testRequestAvailable(),
    RequestApprovedEntry(
      id: 'i',
      seq: 1,
      createdAt: t,
      read: false,
      title: 'Dune',
    ),
    RequestDeclinedEntry(
      id: 'j',
      seq: 1,
      createdAt: t,
      read: false,
      title: 'Dune',
    ),
    testContactReminder(),
    ReportResolvedEntry(
      id: 'k',
      seq: 1,
      createdAt: t,
      read: false,
      reportId: 'r',
      outcome: ReportOutcome.fixed,
      itemId: 'm1',
      title: 'Dune',
    ),
  ];

  test('i 20 tipi, uno per tipo', () {
    final types = {
      for (final e in [...server, ...forYou]) e.runtimeType,
    };
    expect(types, hasLength(20));
  });

  for (final e in server) {
    test('Server: ${e.runtimeType}', () => expect(isServerEntry(e), isTrue));
  }
  for (final e in forYou) {
    test('Per te: ${e.runtimeType}', () => expect(isServerEntry(e), isFalse));
  }
}
