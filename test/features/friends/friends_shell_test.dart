import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/page_transitions.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/user_avatar.dart';

import '../../support/avatar_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  Future<void> pumpShell(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(friends: true),
      List<Override> overrides = const []}) async {
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        ...socialTestOverrides(api, events: events.stream, features: features),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        ...overrides,
      ],
    );
    await tester.pump();
  }

  testWidgets('senza la funzione amici: niente icona', (tester) async {
    await pumpShell(tester, features: SocialFeatures.none);
    expect(find.byKey(const Key('friends-button')), findsNothing);
  });

  testWidgets('icona con il numero delle richieste; apre e chiude il pannello',
      (tester) async {
    api.snapshot = FriendsSnapshot(incoming: [
      testPerson('u3', 'Peach'),
      testPerson('u4', 'Daisy'),
    ]);
    await pumpShell(tester);
    await tester.pump();
    expect(find.byKey(const Key('friends-button')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final loads = api.calls.where((call) => call == 'friends').length;

    // Apre (e rilegge); Esc chiude solo il pannello.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);
    expect(api.calls.where((call) => call == 'friends').length, loads + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Un clic fuori chiude.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Anche la ×.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });

  testWidgets('Esc con il menu ⋯ aperto: chiude prima il menu, poi il pannello',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Rimuovi dagli amici'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Rimuovi dagli amici'), findsNothing);
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });

  testWidgets('con un vero router: aprendo il pannello il campo ha il fuoco',
      (tester) async {
    // Nell'app vera la shell sta dentro un navigatore annidato che ha già un
    // figlio col fuoco: `autofocus` da solo non basta (come `home:` nei test).
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: appShellBuilder,
          routes: [
            GoRoute(
                path: '/home',
                pageBuilder: (context, state) => shellPage(
                    context, state, const Text('home'),
                    underBar: false)),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        ...socialTestOverrides(api, events: events.stream),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('friends-search')));
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('richiesta in arrivo: scheda con Accetta', (tester) async {
    await pumpShell(tester);
    events.add(friendRequestReceived('u3', 'Peach'));
    await tester.pumpAndSettle();
    expect(find.text('Peach vuole essere tuo amico'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const Key('friend-request-card')),
        matching: find.text('Accetta')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('accept u3'));
    expect(find.text('Peach vuole essere tuo amico'), findsNothing);
  });

  testWidgets('richiesta in arrivo: l\'avatar di chi chiede, cercato per id',
      (tester) async {
    final urls = <String>[];
    await pumpShell(tester, overrides: [
      captureImageUrls(urls),
      // Il nome non corrisponde: chi chiede si cerca per id.
      avatarsFor(const [
        UserAvatarInfo(userId: 'u3', name: 'Peach Toadstool', imageTag: 't3'),
      ]),
    ]);
    events.add(friendRequestReceived('u3', 'Peach'));
    await tester.pumpAndSettle();
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    final card = find.byKey(const Key('friend-request-card'));
    expect(find.descendant(of: card, matching: find.byType(UserAvatar)),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.byIcon(LucideIcons.userPlus)),
        findsNothing);
    expect(urls, contains('https://media.example.com/UserImage?userId=u3&tag=t3'));
  });

  testWidgets('"Ho un codice": il primo Esc chiude il campo, il secondo il '
      'pannello', (tester) async {
    await pumpShell(tester,
        features: const SocialFeatures(friends: true, parties: true));
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho un codice'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('party-code-field')), 'K7P');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('party-code-field')), findsNothing);
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });

  testWidgets('con il pannello aperto, la funzione amici che sparisce lo '
      'chiude davvero', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final features = container.read(socialAvailabilityProvider.notifier)
        as FakeSocialAvailability;
    expect(container.read(shellPanelProvider), ShellPanel.friends);
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);

    features.set(SocialFeatures.none);
    await tester.pumpAndSettle();
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Tornata la funzione il pannello non si riapre da solo.
    features.set(const SocialFeatures(friends: true));
    await tester.pumpAndSettle();
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });
}
