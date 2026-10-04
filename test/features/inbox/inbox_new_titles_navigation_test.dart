import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  testWidgets('una riga delle novità apre la scheda e chiude il pannello',
      (tester) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: [
        testNewTitles(
          movies: const [NewTitleMovie(itemId: 'm1', name: 'Dune')],
          series: const [
            NewTitleSeries(seriesId: 's1', name: 'The Bear', episodes: [
              NewTitleEpisode(season: 1, episode: 1),
            ]),
          ],
        ),
      ], unread: 1);
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
          path: '/item/:id',
          builder: (context, state) =>
              Text('scheda ${state.pathParameters['id']}'),
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
            features: const SocialFeatures(inbox: true)),
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

    await tester.tap(find.text('The Bear · S1 E1'));
    await tester.pumpAndSettle();

    expect(find.text('scheda s1'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });
}
