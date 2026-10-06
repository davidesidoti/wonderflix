import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';

void main() {
  ProviderContainer containerFor(SessionState session) => ProviderContainer.test(
        overrides: [
          sessionControllerProvider
              .overrideWith(() => FakeSessionController(session)),
        ],
        retry: (_, _) => null,
      );

  test('isAdmin solo con un admin collegato', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    expect(containerFor(const SessionSignedIn(admin)).read(isAdminProvider),
        isTrue);
    expect(containerFor(const SessionSignedIn(testUser)).read(isAdminProvider),
        isFalse);
    expect(containerFor(const SessionSignedOut()).read(isAdminProvider),
        isFalse);
  });

  test('isAdmin segue la sessione', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    final fake = FakeSessionController(const SessionSignedIn(admin));
    final container = ProviderContainer.test(
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
      retry: (_, _) => null,
    );
    expect(container.read(isAdminProvider), isTrue);

    fake.set(const SessionSignedIn(testUser));
    expect(container.read(isAdminProvider), isFalse);
  });
}
