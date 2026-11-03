import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/downloads/download_search_controller.dart';
import 'package:wonderflix/features/downloads/downloads_controller.dart';
import 'package:wonderflix/features/downloads/downloads_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart' show testAdmin;
import '../../support/download_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';

const _key = 'movie:1';

void main() {
  late FakeDownloadsApi api;

  setUp(() => api = FakeDownloadsApi());

  ProviderContainer container({bool jobs = false}) {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        downloadsApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(SessionSignedIn(testAdmin)),
        ),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(
            SocialFeatures(
              downloads: true,
              downloadsSearchJobs: jobs,
              known: true,
            ),
          ),
        ),
      ],
    );
    c.listen(downloadsControllerProvider, (_, _) {});
    return c;
  }

  test('GrabReloadsTheOverview', () async {
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    await c.read(downloadSearchControllerProvider(_key).future);
    await c.read(downloadsControllerProvider.future);
    api.calls.clear();

    final failure = await c
        .read(downloadSearchControllerProvider(_key).notifier)
        .grab(testCandidate());
    await c.read(downloadsControllerProvider.future);

    expect(failure, isNull);
    expect(api.calls, ['grab movie:1 g1 3', 'overview']);
    sub.close();
  });

  test('ALightenGrabReachesTheApi', () async {
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    await c.read(downloadSearchControllerProvider(_key).future);
    api.calls.clear();
    final notifier = c.read(downloadSearchControllerProvider(_key).notifier);

    expect(await notifier.grab(testCandidate(), lighten: true), isNull);
    expect(await notifier.grabRelease(testCandidate().release, lighten: true),
        isNull);
    expect(await notifier.grabRelease(testCandidate().release), isNull);

    expect(api.calls.where((c) => c.startsWith('grab')), [
      'grab movie:1 g1 3 lighten',
      'grab movie:1 g1 3 lighten',
      'grab movie:1 g1 3',
    ]);
    sub.close();
  });

  test('AGrabOfAnExistingTorrentReturnsIt', () async {
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    await c.read(downloadSearchControllerProvider(_key).future);
    final notifier = c.read(downloadSearchControllerProvider(_key).notifier);
    api.nextActionFailure = DownloadsFailure.refused;
    api.nextActionExisting = const ExistingTorrent(hash: 'abc', name: 'Film');

    final result = await notifier.grabOrExisting(testCandidate().release);

    expect(result.failure, DownloadsFailure.refused);
    expect(result.existing?.hash, 'abc');
    expect(c.read(downloadGrabbingProvider(_key)), isFalse);

    api.calls.clear();
    expect(await notifier.importExisting('abc'), isNull);
    await c.read(downloadsControllerProvider.future);
    expect(api.calls, ['importExisting movie:1 abc', 'overview']);

    api.nextActionFailure = DownloadsFailure.noFiles;
    expect(await notifier.importExisting('abc'), DownloadsFailure.noFiles);
    sub.close();
  });

  test('GrabIsDisabledUntilItAnswers', () async {
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    await c.read(downloadSearchControllerProvider(_key).future);
    final notifier = c.read(downloadSearchControllerProvider(_key).notifier);
    expect(notifier.grabbing, isFalse);

    final gate = api.actionGate = Completer<void>();
    final pending = notifier.grab(testCandidate());
    expect(notifier.grabbing, isTrue);
    expect(c.read(downloadGrabbingProvider(_key)), isTrue);

    gate.complete();
    await pending;
    expect(notifier.grabbing, isFalse);
    sub.close();
  });

  test('ExpiredIsReturned', () async {
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    final before = await c.read(downloadSearchControllerProvider(_key).future);
    api.nextActionFailure = DownloadsFailure.expired;

    final failure = await c
        .read(downloadSearchControllerProvider(_key).notifier)
        .grab(testCandidate());

    expect(failure, DownloadsFailure.expired);
    expect(c.read(downloadSearchControllerProvider(_key)).value, before);
    expect(c.read(downloadGrabbingProvider(_key)), isFalse);
    sub.close();
  });

  group('GrabAll', () {
    final releases = [for (final n in [1, 2, 3]) testRelease(guid: 'e$n')];

    test('GrabsInOrderAndReloadsTheOverviewOnce', () async {
      final c = container();
      final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
      await c.read(downloadSearchControllerProvider(_key).future);
      await c.read(downloadsControllerProvider.future);
      api.calls.clear();

      final result = await c
          .read(downloadSearchControllerProvider(_key).notifier)
          .grabAll(releases);
      await c.read(downloadsControllerProvider.future);

      expect((result.started, result.failed, result.firstFailure),
          (3, 0, null));
      expect(api.calls, [
        'grab movie:1 e1 3',
        'grab movie:1 e2 3',
        'grab movie:1 e3 3',
        'overview',
      ]);
      expect(c.read(downloadGrabbingProvider(_key)), isFalse);
      sub.close();
    });

    test('GrabbingStaysTrueForTheWholeRunAndProgressCounts', () async {
      final c = container();
      final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
      await c.read(downloadSearchControllerProvider(_key).future);
      final notifier = c.read(downloadSearchControllerProvider(_key).notifier);
      api.actionGates.addAll([for (var i = 0; i < 3; i++) Completer<void>()]);
      final gates = [...api.actionGates];

      final pending = notifier.grabAll(releases);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(downloadGrabProgressProvider(_key)), (1, 3));
      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      // Tra un grab e l'altro il flag non cade.
      expect(notifier.grabbing, isTrue);
      expect(c.read(downloadGrabProgressProvider(_key)), (2, 3));

      gates[1].complete();
      gates[2].complete();
      await pending;
      expect(notifier.grabbing, isFalse);
      expect(c.read(downloadGrabProgressProvider(_key)), isNull);
      sub.close();
    });

    test('AFailureDoesNotStopTheOthers', () async {
      final c = container();
      final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
      await c.read(downloadSearchControllerProvider(_key).future);
      api.nextActionFailure = DownloadsFailure.refused;

      final result = await c
          .read(downloadSearchControllerProvider(_key).notifier)
          .grabAll(releases);

      expect((result.started, result.failed, result.firstFailure),
          (2, 1, DownloadsFailure.refused));
      expect(api.calls.where((x) => x.startsWith('grab')), hasLength(3));
      sub.close();
    });

    test('NothingStartedDoesNotReloadTheOverview', () async {
      final c = container();
      final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
      await c.read(downloadSearchControllerProvider(_key).future);
      await c.read(downloadsControllerProvider.future);
      api.calls.clear();
      api.nextActionFailure = DownloadsFailure.busy;

      final result = await c
          .read(downloadSearchControllerProvider(_key).notifier)
          .grabAll([releases.first]);
      await Future<void>.delayed(Duration.zero);

      expect(result.started, 0);
      expect(api.calls, ['grab movie:1 e1 3']);
      sub.close();
    });

    test('ClosingThePageStopsTheRun', () async {
      final c = container();
      final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
      await c.read(downloadSearchControllerProvider(_key).future);
      final notifier = c.read(downloadSearchControllerProvider(_key).notifier);
      final gate = Completer<void>();
      api.actionGates.add(gate);

      final pending = notifier.grabAll(releases);
      await Future<void>.delayed(Duration.zero);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await pending;

      expect(api.calls.where((x) => x.startsWith('grab')), ['grab movie:1 e1 3']);
    });
  });

  test('DisposingCancelsTheSearch', () async {
    api.searchGate = Completer();
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final token = api.searchToken!;
    expect(token.isCancelled, isFalse);

    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(token.isCancelled, isTrue);
  });

  test('usesTheOldSearch', () async {
    final c = container();
    final sub = c.listen(downloadSearchControllerProvider(_key), (_, _) {});
    await c.read(downloadSearchControllerProvider(_key).future);
    await c.read(downloadSearchControllerProvider(_key).notifier).searchAgain();

    expect(api.calls.where((x) => x.contains(_key)),
        ['search movie:1', 'search movie:1']);
    sub.close();
  });

  // Con `downloadsSearchJobs`: start, poi lo stato ogni 3 s (spec W §5.2).
  group('SearchJobs', () {
    final startedAt = DateTime.utc(2026, 11, 1, 10);
    DownloadSearchStatus status(
      DownloadSearchJobState state, {
      DownloadSearch? result,
    }) =>
        DownloadSearchStatus(
          key: _key,
          state: state,
          startedAt: startedAt,
          service: 'Radarr',
          result: result,
        );
    final running = status(DownloadSearchJobState.running);
    final done = status(DownloadSearchJobState.done, result: testSearch());
    const network = DownloadsException(DownloadsFailure.network);
    const poll = DownloadSearchController.pollInterval;

    // Apre la pagina: ascolta il controller.
    (ProviderContainer, ProviderSubscription<AsyncValue<DownloadSearch>>)
        open() {
      final c = container(jobs: true);
      return (c, c.listen(downloadSearchControllerProvider(_key), (_, _) {}));
    }

    AsyncValue<DownloadSearch> stateOf(ProviderContainer c) =>
        c.read(downloadSearchControllerProvider(_key));
    DownloadSearchRunning? runningOf(ProviderContainer c) =>
        c.read(downloadSearchRunningProvider(_key));
    Iterable<String> callsOf(String key) =>
        api.calls.where((x) => x.contains(key));

    test('startsThenPollsUntilDone', () {
      fakeAsync((async) {
        api.searchStatuses.addAll([running, running, done]);
        final (c, sub) = open();
        async.elapse(const Duration(seconds: 6));

        expect(stateOf(c).value?.title, testSearch().title);
        expect(runningOf(c), isNull);
        expect(callsOf(_key),
            ['start movie:1', 'status movie:1', 'status movie:1']);
        sub.close();
      });
    });

    test('exposesStartedAtAndServiceWhileRunning', () {
      fakeAsync((async) {
        api.searchStatuses.addAll([running, done]);
        final (c, sub) = open();
        async.elapse(Duration.zero);

        expect(stateOf(c).isLoading, isTrue);
        expect(runningOf(c),
            (startedAt: startedAt, service: 'Radarr', reconnecting: false));
        async.elapse(poll);
        expect(runningOf(c), isNull);
        sub.close();
      });
    });

    test('aFinishedErrorIsShownWithoutSearchingAgain', () {
      fakeAsync((async) {
        const failed = DownloadSearch(
          key: _key,
          kind: DownloadKind.movie,
          title: 'Film',
          runtimeMinutes: 100,
          validCount: 0,
          totalCount: 0,
          error: 'Unreachable',
        );
        api.searchStatuses
            .add(status(DownloadSearchJobState.done, result: failed));
        final (c, sub) = open();
        async.elapse(const Duration(seconds: 10));

        expect(stateOf(c).value?.error, 'Unreachable');
        expect(callsOf(_key), ['start movie:1']);
        sub.close();
      });
    });

    test('aRestartedPluginStartsAgain', () {
      fakeAsync((async) {
        api.searchStatuses
            .addAll([running, status(DownloadSearchJobState.none), done]);
        final (c, sub) = open();
        async.elapse(poll * 2);

        expect(callsOf(_key),
            ['start movie:1', 'status movie:1', 'start movie:1']);
        expect(stateOf(c).hasValue, isTrue);
        sub.close();
      });
    });

    test('transientNetworkErrorsKeepPolling', () {
      fakeAsync((async) {
        api.searchStatuses.addAll([running, network, done]);
        final (c, sub) = open();
        async.elapse(poll);

        expect(runningOf(c)?.reconnecting, isTrue);
        expect(stateOf(c).isLoading, isTrue);
        async.elapse(poll);
        expect(stateOf(c).hasValue, isTrue);
        sub.close();
      });
    });

    test('threeNetworkErrorsShowTheError', () {
      fakeAsync((async) {
        api.searchStatuses.addAll([running, network, network, network]);
        final (c, sub) = open();
        async.elapse(poll * 2);
        expect(stateOf(c).isLoading, isTrue);
        async.elapse(poll);

        expect(stateOf(c).error, network);
        expect(runningOf(c), isNull);

        api.calls.clear();
        api.searchStatuses.add(done);
        c.read(downloadSearchControllerProvider(_key).notifier).retry();
        async.elapse(Duration.zero);
        expect(callsOf(_key), ['start movie:1']);
        expect(stateOf(c).hasValue, isTrue);
        sub.close();
      });
    });

    test('closingThePageStopsPolling', () {
      fakeAsync((async) {
        api.searchStatuses.addAll([running, running, running, running]);
        final (c, sub) = open();
        async.elapse(poll);
        final before = callsOf(_key).length;

        sub.close();
        c.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(callsOf(_key), hasLength(before));
      });
    });

    test('searchAgainSendsAgain', () {
      fakeAsync((async) {
        final (c, sub) = open();
        async.elapse(Duration.zero);
        api.calls.clear();

        c.read(downloadSearchControllerProvider(_key).notifier).searchAgain();
        async.elapse(Duration.zero);
        expect(callsOf(_key), ['start movie:1 again']);
        expect(stateOf(c).hasValue, isTrue);
        sub.close();
      });
    });

    test('missingIsInvalid', () {
      fakeAsync((async) {
        api.searchStatuses
            .addAll([running, status(DownloadSearchJobState.missing)]);
        final (c, sub) = open();
        async.elapse(poll);

        expect(
          stateOf(c).error,
          isA<DownloadsException>()
              .having((e) => e.failure, 'failure', DownloadsFailure.invalid),
        );
        expect(runningOf(c), isNull);
        sub.close();
      });
    });
  });
}
