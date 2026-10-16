import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  testWidgets('"Match del film" nel pannello Amici apre una sala e chiude il '
      'pannello', (tester) async {
    final match = FakeMatchApi();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
          ),
        ),
      ),
      GoRoute(
          path: '/match/:id',
          builder: (_, state) => Text('pagina ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      ...socialTestOverrides(FakeSocialApi(),
          features: const SocialFeatures(friends: true, match: true)),
      matchApiProvider.overrideWithValue(match),
      syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      partyChannelApiProvider
          .overrideWithValue(FakePartyChannelApi()..install()),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.friends);
    await tester.pump();

    await tester.tap(find.byKey(const Key('friends-match')));
    await tester.pumpAndSettle();

    expect(match.calls, ['open']);
    expect(find.text('pagina r1'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });
}
