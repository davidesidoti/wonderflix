import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/calendar/calendar_providers.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeHomeApi api;

  ProviderContainer containerWith({required bool calendar}) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        homeApiProvider.overrideWithValue(api),
        socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(SocialFeatures(calendar: calendar)),
        ),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => api = FakeHomeApi());

  test('WeekProviderAsksTodayPlusSeven', () async {
    final container = containerWith(calendar: true);
    // il provider si costruisce alla prima lettura: l'orologio va fermato lì
    await withClock(Clock.fixed(DateTime(2026, 11, 28, 21)), () {
      final sub = container.listen(calendarWeekProvider, (_, _) {});
      addTearDown(sub.close);
      return container.read(calendarWeekProvider.future);
    });
    // a cavallo di due mesi: una sola richiesta, da oggi a oggi + 7
    expect(api.calendarCalls, [
      (DateTime(2026, 11, 28), DateTime(2026, 12, 5)),
    ]);
  });

  test('WeekProviderAsksNothingWithoutTheFeature', () async {
    final container = containerWith(calendar: false);
    final sub = container.listen(calendarWeekProvider, (_, _) {});
    addTearDown(sub.close);
    final page = await container.read(calendarWeekProvider.future);
    expect(api.calendarCalls, isEmpty);
    expect(page.movies, isEmpty);
    expect(page.episodes, isEmpty);
  });
}
