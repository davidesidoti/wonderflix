import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final failure =
        await c.read(spaceControllerProvider.notifier).keep('movie:1', 'Film');
    expect(failure, isNull);
    expect(api.calls, ['overview', 'keep movie:1 Film', 'overview']);
  });
}
