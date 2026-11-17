import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi social;
  late FakeMatchApi match;
  late SharedPreferences prefs;

  Future<ProviderContainer> pumpPanel(WidgetTester tester) async {
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
          builder: (_, state) => Scaffold(
              body: MatchScreen(roomId: state.pathParameters['id']!))),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      ...socialTestOverrides(social,
          features: const SocialFeatures(friends: true, match: true)),
      matchApiProvider.overrideWithValue(match),
      sharedPreferencesProvider.overrideWithValue(prefs),
      libraryApiProvider.overrideWithValue(FakeLibraryApi()),
      syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      partyChannelApiProvider
          .overrideWithValue(FakePartyChannelApi()..install()),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.friends);
    await tester.pump();
    return container;
  }

  setUp(() async {
    social = FakeSocialApi();
    match = FakeMatchApi();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('"Apri un Match" nel pannello Amici apre una sala e chiude il '
      'pannello', (tester) async {
    final container = await pumpPanel(tester);
    await tester.tap(find.byKey(const Key('friends-match')));
    await tester.pumpAndSettle();

    expect(match.calls, ['open']);
    expect(find.byType(MatchScreen), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('"Invita a un Match" dal ⋯ apre la sala e invita l\'amico',
      (tester) async {
    social.snapshot =
        FriendsSnapshot(friends: [testFriend('u2', 'sara', online: true)]);
    final container = await pumpPanel(tester);
    await tester.pump();
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invita a un Match'));
    await tester.pumpAndSettle();

    expect(match.calls, ['open', 'invite r1 u2']);
    expect(find.byType(MatchScreen), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(
        find.descendant(
            of: find.byKey(const Key('match-invite-u2')),
            matching: find.text('Invitato')),
        findsOneWidget,
        reason: "la pagina sa dell'invito partito dal pannello");
  });
}
