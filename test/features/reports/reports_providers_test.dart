import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/reports/reports_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/report_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  ProviderContainer container({
    JellyfinUser user = testUser,
    SocialFeatures features = const SocialFeatures(reports: true),
    FakeLibraryApi? library,
  }) {
    final c = ProviderContainer.test(overrides: [
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
      if (library != null) libraryApiProvider.overrideWithValue(library),
    ], retry: (_, _) => null);
    return c;
  }

  test('canManageSubtitles: admin sì, spunta sì, nessuno dei due no, senza reports no',
      () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    const manager =
        JellyfinUser(id: 'u1', name: 'Mario', enableSubtitleManagement: true);

    expect(container(user: admin).read(canManageSubtitlesProvider), isTrue);
    expect(container(user: manager).read(canManageSubtitlesProvider), isTrue);
    expect(container().read(canManageSubtitlesProvider), isFalse);
    expect(
        container(user: admin, features: const SocialFeatures())
            .read(canManageSubtitlesProvider),
        isFalse);
    expect(
        container(user: manager, features: const SocialFeatures())
            .read(canManageSubtitlesProvider),
        isFalse);
  });

  test('canManageSubtitles è falso senza sessione', () {
    final c = ProviderContainer.test(overrides: [
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedOut())),
      socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(const SocialFeatures(reports: true))),
    ]);
    expect(c.read(canManageSubtitlesProvider), isFalse);
  });

  test('itemMediaInfoProvider legge le info dell\'utente corrente', () async {
    final library = FakeLibraryApi();
    final info = testMediaInfo();
    library.mediaInfoById['e1'] = info;
    final c = container(library: library);
    c.listen(itemMediaInfoProvider('e1'), (_, _) {});
    expect(await c.read(itemMediaInfoProvider('e1').future), same(info));
    expect(library.mediaInfoCalls, ['e1']);
  });
}
