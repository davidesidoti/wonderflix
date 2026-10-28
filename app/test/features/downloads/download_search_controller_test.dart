import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  ProviderContainer container() {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        downloadsApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(SessionSignedIn(testAdmin)),
        ),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(
            const SocialFeatures(downloads: true, known: true),
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
}
