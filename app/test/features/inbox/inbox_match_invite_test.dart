import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeMatchApi match;
  setUp(() => match = FakeMatchApi());

  /// Apre il pannello con le voci date dentro un router che ha anche la
  /// scheda `/item/:id`.
  Future<ProviderContainer> pumpPanel(
      WidgetTester tester, List<InboxEntry> entries) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: entries, unread: 1);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
            ),
          ),
        ),
        GoRoute(
          path: '/match/:id',
          builder: (context, state) =>
              Text('pagina ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const SizedBox.shrink()),
        ...socialTestOverrides(api,
            features: const SocialFeatures(inbox: true, match: true)),
        matchApiProvider.overrideWithValue(match),
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
    final container =
        ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    return container;
  }

  testWidgets('invito al match: chi invita, Unisciti entra, apre la sala e '
      'chiude il pannello', (tester) async {
    match.rooms['r2'] = testMatchState(roomId: 'r2', creatorId: 'u2', creatorName: 'Luigi');
    final container = await pumpPanel(tester, [testMatchInviteEntry()]);

    expect(find.textContaining('Luigi ti invita a un match'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-match-join-mi1')));
    await tester.pumpAndSettle();

    expect(match.calls, ['join r2']);
    expect(find.text('pagina r2'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('anOldMatchInviteSaysWhy', (tester) async {
    match.failures['join r2'] = const MatchException(MatchFailure.started);
    final container = await pumpPanel(tester, [testMatchInviteEntry()]);

    await tester.tap(find.byKey(const Key('inbox-match-join-mi1')));
    await tester.pumpAndSettle();

    expect(find.text('Il match è già iniziato'), findsOneWidget);
    expect(find.textContaining('pagina'), findsNothing);
    expect(container.read(shellPanelProvider), ShellPanel.inbox);
  });
}
