import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/downloads/downloads_controller.dart';
import 'package:wonderflix/features/downloads/downloads_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart' show testAdmin;
import '../../support/download_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeDownloadsApi api;

  setUp(() => api = FakeDownloadsApi());

  ProviderContainer container({bool admin = true, bool downloads = true}) {
    final c = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        downloadsApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(
            SessionSignedIn(admin ? testAdmin : testUser),
          ),
        ),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(
            SocialFeatures(downloads: downloads, known: true),
          ),
        ),
      ],
    );
    c.listen(downloadsControllerProvider, (_, _) {});
    return c;
  }

  test('NonAdminsGetNothing', () async {
    final c = container(admin: false);
    final overview = await c.read(downloadsControllerProvider.future);
    expect(overview.enabled, isFalse);
    expect(api.calls, isEmpty);
  });

  test('WithoutTheFeatureGetsNothing', () async {
    final c = container(downloads: false);
    final overview = await c.read(downloadsControllerProvider.future);
    expect(overview.enabled, isFalse);
    expect(api.calls, isEmpty);
  });

  test('OnlyTheLastAnswerCounts', () async {
    final first = Completer<DownloadsOverview>();
    final second = Completer<DownloadsOverview>();
    api.overviewGates.addAll([first, second]);
    final c = container();
    const stale = DownloadsOverview(enabled: true, sonarrError: 'stale');
    const fresh = DownloadsOverview(enabled: true, sonarrError: 'fresh');
    // La lettura di build() è la prima; reload() la seconda.
    final reload = c.read(downloadsControllerProvider.notifier).reload();
    second.complete(fresh);
    await reload;
    first.complete(stale);
    final overview = await c.read(downloadsControllerProvider.future);
    expect(overview.sonarrError, 'fresh');
    expect(c.read(downloadsControllerProvider).value?.sonarrError, 'fresh');
  });
}
