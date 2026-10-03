import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/party_mode_menu.dart';
import 'package:wonderflix/features/watch_party/party_mode_preference.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeSocialApi social;
  late StreamController<ServerEvent> events;
  late SharedPreferences prefs;
  final film = testItem(id: 'm1', name: 'Dune');

  setUp(() {
    api = FakeSyncPlayApi();
    social = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('create')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pump(WidgetTester tester,
      {SocialFeatures features =
          const SocialFeatures(friends: true, parties: true)}) async {
    SharedPreferences.setMockInitialValues(
        {PartyModePreference.key: 'Friends'});
    prefs = await SharedPreferences.getInstance();
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => Builder(
              builder: (buttonContext) => TextButton(
                onPressed: () =>
                    unawaited(watchTogether(buttonContext, ref, film)),
                child: const Text('insieme'),
              ),
            ),
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider
            .overrideWith(() => FakeSocialAvailability(features)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  }

  Future<void> leave(WidgetTester tester) async {
    final container =
        ProviderScope.containerOf(tester.element(find.text('insieme')));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('tre modalità, l\'ultima evidenziata; la scelta crea e registra',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    expect(find.text('Pubblico'), findsOneWidget);
    expect(find.text('Lo vedono tutti, avviso a tutti'), findsOneWidget);
    expect(find.text('Solo amici'), findsOneWidget);
    expect(find.text('Privato'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('party-mode-Public'))).width,
        partyModeMenuWidth);
    expect(
        find.descendant(
            of: find.byKey(const Key('party-mode-Friends')),
            matching: find.byKey(const Key('party-mode-selected'))),
        findsOneWidget);

    await tester.tap(find.text('Privato'));
    await tester.pumpAndSettle();
    expect(api.calls.first, 'create Mario · Dune');
    expect(social.calls, contains('register g1 Private'));
    expect(prefs.getString(PartyModePreference.key), 'Private');
    await leave(tester);
  });

  testWidgets('chiuso senza scegliere: niente gruppo', (tester) async {
    await pump(tester);
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('senza la funzione parties: nessun menu, come prima',
      (tester) async {
    await pump(tester,
        features: const SocialFeatures(friends: true, parties: false));
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(api.calls.first, 'create Mario · Dune');
    expect(social.calls, isNot(contains(startsWith('register'))));
    await leave(tester);
  });

  testWidgets('funzioni del plugin non ancora note: nessun menu, come prima',
      (tester) async {
    await pump(tester, features: SocialFeatures.unknown);
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(api.calls.first, 'create Mario · Dune');
    expect(social.calls, isNot(contains(startsWith('register'))));
    await leave(tester);
  });

  testWidgets('dentro un gruppo: nessun menu, cambia la coda', (tester) async {
    await pump(tester);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    final container =
        ProviderScope.containerOf(tester.element(find.text('insieme')));
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(api.calls, contains('queue m1'));
    expect(api.calls, isNot(contains(startsWith('create'))));
    expect(social.calls, isNot(contains(startsWith('register'))));
    await leave(tester);
  });
}
