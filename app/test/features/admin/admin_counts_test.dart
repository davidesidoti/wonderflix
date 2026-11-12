import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/features/admin/admin_counts.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/download_fakes.dart';

DownloadItem _item(String key, DownloadState state) => DownloadItem(
      key: key,
      kind: DownloadKind.movie,
      title: key,
      state: state,
      availableSince: DateTime.utc(2026, 11, 1),
    );

ScheduledTask _task(String id, TaskState state) =>
    ScheduledTask(id: id, name: id, state: state);

void main() {
  late FakeAdminApi api;
  late FakeDownloadsApi downloads;

  setUp(() {
    api = FakeAdminApi();
    downloads = FakeDownloadsApi();
  });

  ProviderContainer makeContainer({bool downloadsOn = true}) {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(
        api,
        downloads: downloads,
        features: SocialFeatures(inbox: true, downloads: downloadsOn),
      ),
      retry: (_, _) => null,
    );
    container.listen(adminCountsProvider, (_, _) {});
    return container;
  }

  test('counts are read every 60 s', () {
    expect(AdminCountsController.every, const Duration(seconds: 60));
  });

  test('counts playing sessions, running tasks and needsYou items', () async {
    api
      ..sessionsValue = [
        testSession('a', 'anna', playing: testMovie),
        testSession('b', 'bruno', playing: testMovie),
        testSession('c', 'carla'),
      ]
      ..tasksValue = [
        _task('t1', TaskState.running),
        _task('t2', TaskState.cancelling),
        _task('t3', TaskState.idle),
      ];
    downloads.overviewValue = DownloadsOverview(enabled: true, waiting: [
      for (var i = 0; i < 3; i++) _item('n$i', DownloadState.needsYou),
      _item('w', DownloadState.waiting),
    ]);
    final container = makeContainer();
    await pumpEventQueue();

    final counts = container.read(adminCountsProvider).value!;
    expect(
        (counts.playing, counts.running, counts.needsYou), (2, 2, 3));
  });

  test('downloads not enabled → no overview call', () async {
    final container = makeContainer(downloadsOn: false);
    await pumpEventQueue();

    expect(downloads.calls, isEmpty);
    final counts = container.read(adminCountsProvider).value!;
    expect(counts.needsYou, isNull);
    expect(counts.playing, 0);
  });

  test('a failed read keeps the previous value', () async {
    api
      ..sessionsValue = [testSession('a', 'anna', playing: testMovie)]
      ..tasksValue = [_task('t1', TaskState.running)];
    final container = makeContainer();
    await pumpEventQueue();
    expect(container.read(adminCountsProvider).value!.running, 1);

    api
      ..sessionsValue = [
        testSession('a', 'anna', playing: testMovie),
        testSession('b', 'bruno', playing: testMovie),
      ]
      ..tasksError = Exception('boom');
    await container.read(adminCountsProvider.notifier).refresh();

    final counts = container.read(adminCountsProvider).value!;
    expect(counts.running, 1);
    expect(counts.playing, 2);
  });

  group('adminTabCount', () {
    Future<int?> countOf(
      WidgetTester tester,
      ProviderContainer container,
      AdminTab tab, {
      required AdminTab current,
    }) async {
      int? result;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, ref, _) {
          result = adminTabCount(ref, tab, current: current);
          return const SizedBox();
        }),
      ));
      return result;
    }

    testWidgets('other tabs read the counts, 0 and unlisted tabs are null',
        (tester) async {
      api
        ..sessionsValue = [testSession('a', 'anna', playing: testMovie)]
        ..tasksValue = [_task('t1', TaskState.idle)];
      final container = makeContainer();
      await tester.pump(const Duration(milliseconds: 1));

      expect(
          await countOf(tester, container, AdminTab.sessions,
              current: AdminTab.activity),
          1);
      expect(
          await countOf(tester, container, AdminTab.maintenance,
              current: AdminTab.activity),
          isNull);
      expect(
          await countOf(tester, container, AdminTab.space,
              current: AdminTab.activity),
          isNull);
      // Il timer del prossimo giro non deve restare in sospeso.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });
}
