import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/match/match_entry.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeMatchApi match;
  var pressed = 0;

  setUp(() {
    match = FakeMatchApi();
    pressed = 0;
  });

  Future<ProviderContainer> pumpButton(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(friends: true, match: true),
      SyncPlayAccess? access}) async {
    await pumpApp(
      tester,
      Scaffold(body: Center(child: MatchButton(onPressed: () => pressed++))),
      overrides: [
        ...socialTestOverrides(FakeSocialApi(), features: features),
        matchApiProvider.overrideWithValue(match),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        if (access != null) syncPlayAccessProvider.overrideWithValue(access),
      ],
    );
    return ProviderScope.containerOf(tester.element(find.byType(MatchButton)));
  }

  testWidgets('theEntriesNeedFeatureCanCreateAndNoRoom', (tester) async {
    final container = await pumpButton(tester);
    expect(find.byKey(const Key('match-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('match-button')));
    expect(pressed, 1);

    // Già in una sala: niente pulsante.
    await container.read(matchRoomProvider.notifier).open();
    await tester.pump();
    expect(find.byKey(const Key('match-button')), findsNothing);
    await container.read(matchRoomProvider.notifier).leave();
    await tester.pump();
    expect(find.byKey(const Key('match-button')), findsOneWidget);
  });

  testWidgets('senza la funzione o senza il permesso di creare, niente',
      (tester) async {
    await pumpButton(tester, features: const SocialFeatures(friends: true));
    expect(find.byKey(const Key('match-button')), findsNothing);

    // Altro ProviderScope: gli override cambiano di numero.
    await tester.pumpWidget(const SizedBox());
    await pumpButton(tester, access: SyncPlayAccess.joinOnly);
    expect(find.byKey(const Key('match-button')), findsNothing);
  });
}
