import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations_it.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  test('i motivi diventano testi', () {
    final l = AppLocalizationsIt();
    expect(matchFailureText(l, MatchFailure.started), 'Il match è già iniziato');
    expect(matchFailureText(l, MatchFailure.closed), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.notInvited), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.notMember), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.full), 'Sala piena');
    expect(matchFailureText(l, MatchFailure.inAnotherRoom),
        'Sei già in un\'altra sala');
    expect(matchFailureText(l, MatchFailure.network), 'Non riuscito, riprova');
  });

  testWidgets('se l\'invito non riesce la sala resta aperta e lo dice',
      (t) async {
    final match = FakeMatchApi()
      ..failures['invite r1 u2'] = const MatchException(MatchFailure.full);
    bool? opened;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  opened = await openMatchRoomInviting(context, ref, 'u2'),
              child: const Text('invita'),
            ),
          ),
        ),
      ),
      GoRoute(
          path: '/match/:id',
          builder: (_, state) => Scaffold(
              body: Text('pagina ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(t, router, overrides: [
      ...socialTestOverrides(FakeSocialApi(),
          features: const SocialFeatures(friends: true, match: true)),
      matchApiProvider.overrideWithValue(match),
      syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      partyChannelApiProvider
          .overrideWithValue(FakePartyChannelApi()..install()),
    ]);
    await t.tap(find.text('invita'));
    await t.pumpAndSettle();

    expect(opened, isTrue);
    expect(match.calls, ['open', 'invite r1 u2']);
    final container =
        ProviderScope.containerOf(t.element(find.text('pagina r1')));
    expect(container.read(matchRoomProvider), isNotNull);
    expect(match.calls, isNot(contains('leave r1')));
    expect(find.text('Sala piena'), findsOneWidget);
  });
}
