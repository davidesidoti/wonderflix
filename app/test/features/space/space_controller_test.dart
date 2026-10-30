import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/core/space/space_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/space/space_controller.dart';
import 'package:wonderflix/features/space/space_providers.dart';

import '../../support/admin_fakes.dart' show testAdmin;
import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/space_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeSpaceApi api;

  setUp(() => api = FakeSpaceApi());

  ProviderContainer container({bool admin = true}) {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        spaceApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(
            SessionSignedIn(admin ? testAdmin : testUser),
          ),
        ),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(
            const SocialFeatures(space: true, known: true),
          ),
        ),
      ],
    );
    c.listen(spaceControllerProvider, (_, _) {});
    return c;
  }

  test('ANonAdminGetsNothing', () async {
    final c = container(admin: false);
    await c.read(spaceControllerProvider.future);
    expect(api.calls, isEmpty);
  });

  test('KeepThenReloads', () async {
    final c = container();
    await c.read(spaceControllerProvider.future);
    final failure = await c
        .read(spaceControllerProvider.notifier)
        .keep('movie:1', 'Film');
    expect(failure, isNull);
    expect(api.calls, ['overview', 'keep movie:1 Film', 'overview']);
  });

  SpaceOverview at(int day) => SpaceOverview(
    scannedAt: DateTime.utc(2026, 1, day),
    scanning: false,
    breakdown: SpaceOverview.empty.breakdown,
    delete: const [],
    lighten: const [],
    cleanup: const SpaceCleanup(),
    pending: const [],
    kept: const [],
    operations: const [],
    topGenres: const [],
    errors: const SpaceErrors(),
  );

  test('AnOlderReloadNeverOverwritesANewerOne', () async {
    final c = container();
    await c.read(spaceControllerProvider.future);
    final first = Completer<SpaceOverview>();
    final second = Completer<SpaceOverview>();
    api.overviewGates.addAll([first, second]);
    final notifier = c.read(spaceControllerProvider.notifier);
    final a = notifier.reload();
    final b = notifier.reload();
    second.complete(at(2));
    await b;
    first.complete(at(1));
    await a;
    expect(c.read(spaceControllerProvider).value?.scannedAt, at(2).scannedAt);
  });

  test('AFailedReloadKeepsTheData', () async {
    api.overviewValue = at(1);
    final c = container();
    await c.read(spaceControllerProvider.future);
    api.overviewError = const SpaceException(SpaceFailure.network);
    await c.read(spaceControllerProvider.notifier).reload();
    final state = c.read(spaceControllerProvider);
    expect(state, isA<AsyncData<SpaceOverview>>());
    expect(state.value?.scannedAt, at(1).scannedAt);
  });

  test('AFailedKeepReturnsTheFailure', () async {
    final c = container();
    await c.read(spaceControllerProvider.future);
    api.nextActionFailure = SpaceFailure.busy;
    final failure = await c
        .read(spaceControllerProvider.notifier)
        .keep('movie:1', 'F');
    expect(failure, SpaceFailure.busy);
    expect(c.read(spaceControllerProvider).hasError, isFalse);
    expect(api.calls, ['overview', 'keep movie:1 F']);
  });

  test('UnkeepDropPendingAndRecalculateThenReload', () async {
    final c = container();
    await c.read(spaceControllerProvider.future);
    final n = c.read(spaceControllerProvider.notifier);
    expect(await n.unkeep('movie:1'), isNull);
    expect(await n.dropPending('abc'), isNull);
    expect(await n.recalculate(), isNull);
    expect(api.calls, [
      'overview',
      'unkeep movie:1',
      'overview',
      'drop abc',
      'overview',
      'recalculate',
      'overview',
    ]);
  });
}
