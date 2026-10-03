import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/current_party.dart';
import 'package:wonderflix/features/watch_party/party_badge.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeSocialApi social;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSyncPlayApi();
    social = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<ProviderContainer> pumpBadge(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(body: Center(child: PartyBadge(onLeave: () {}))),
      overrides: [
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
      ],
    );
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PartyBadge)));
    container.listen(partyNoticesProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> leave(ProviderContainer c, WidgetTester tester) async {
    await c.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('codice copiato: lo dice la pillola', (tester) async {
    social.details['g1'] =
        const PartyDetails(mode: PartyMode.private, code: 'K7PQ2X');
    final c = await pumpBadge(tester);
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codice K7P-Q2X'));
    await tester.pumpAndSettle();
    expect(c.read(partyNoticesProvider)?.kind, PartyNoticeKind.codeCopied);
    await leave(c, tester);
  });

  testWidgets('party privato appena creato: il codice nella pillola, una volta',
      (tester) async {
    final c = await pumpBadge(tester);
    c
        .read(currentPartyProvider.notifier)
        .registered('g1', PartyMode.private, 'K7PQ2X');
    await tester.pump();
    await tester.pump();
    final notice = c.read(partyNoticesProvider)!;
    expect(notice.kind, PartyNoticeKind.privateCode);
    expect(notice.title, 'K7P-Q2X');
    expect(c.read(currentPartyProvider)!.announceCode, isFalse);
    await leave(c, tester);
  });

  testWidgets('distintivo montato dopo la registrazione: il codice arriva lo '
      'stesso', (tester) async {
    // Come nel player del gruppo, che si apre dopo la registrazione.
    final show = ValueNotifier(false);
    addTearDown(show.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (context, visible, _) => visible
                ? PartyBadge(onLeave: () {})
                : const Text('senza distintivo'),
          ),
        ),
      ),
      overrides: [
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
      ],
    );
    final c = ProviderScope.containerOf(
        tester.element(find.text('senza distintivo')));
    c.listen(partyNoticesProvider, (_, _) {});
    unawaited(c.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    c
        .read(currentPartyProvider.notifier)
        .registered('g1', PartyMode.private, 'K7PQ2X');

    show.value = true;
    await tester.pump();
    await tester.pump();
    expect(c.read(partyNoticesProvider)?.kind, PartyNoticeKind.privateCode);
    expect(c.read(currentPartyProvider)!.announceCode, isFalse);
    await leave(c, tester);
  });

  testWidgets('Invita amici dal player: l\'esito nella pillola',
      (tester) async {
    social.snapshot =
        FriendsSnapshot(friends: [testFriend('u2', 'Luigi', online: true)]);
    final c = await pumpBadge(tester);
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invita amici'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-u2')));
    await tester.pumpAndSettle();
    expect(social.calls, contains('invite g1 u2'));
    final notice = c.read(partyNoticesProvider)!;
    expect(notice.kind, PartyNoticeKind.inviteSent);
    expect(notice.name, 'Luigi');
    await leave(c, tester);
  });

  testWidgets('invito non riuscito: lo dice la pillola', (tester) async {
    social.snapshot =
        FriendsSnapshot(friends: [testFriend('u2', 'Luigi', online: true)]);
    final c = await pumpBadge(tester);
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invita amici'));
    await tester.pumpAndSettle();
    social.nextFailure = SocialFailure.rateLimited;
    await tester.tap(find.byKey(const ValueKey('invite-u2')));
    await tester.pumpAndSettle();
    expect(c.read(partyNoticesProvider)?.kind, PartyNoticeKind.inviteFailed);
    expect(c.read(currentPartyProvider)!.invited, isEmpty);
    await leave(c, tester);
  });
}
