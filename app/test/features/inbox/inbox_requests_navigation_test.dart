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
  /// Apre il pannello con [entries] in un router con la pagina Richieste e
  /// la scheda `/item/:id`.
  Future<(GoRouter, ProviderContainer)> pumpPanel(
      WidgetTester tester, List<InboxEntry> entries) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: entries, unread: entries.length);
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
        GoRoute(path: '/requests', builder: (context, state) => const Text('richieste')),
        GoRoute(path: '/item/:id', builder: (context, state) => const Text('scheda')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider.overrideWithValue((image, fit) => const SizedBox.shrink()),
        ...socialTestOverrides(api, features: const SocialFeatures(inbox: true)),
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
    return (router, container);
  }

  testWidgets('"ha chiesto" apre Richieste su "Da approvare" e chiude il pannello',
      (tester) async {
    final (router, container) = await pumpPanel(tester, [testRequestPending()]);

    await tester.tap(find.text('Garg ha chiesto Dune (2021)'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/requests?tab=pending');
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('"Ora disponibile" apre la scheda, o "Le mie" senza id', (tester) async {
    final (router, container) = await pumpPanel(tester, [
      testRequestAvailable(id: 'r1', seq: 2, title: 'Dune (2021)', itemId: 'ee39'),
      testRequestAvailable(id: 'r2', seq: 1, title: 'Brothers (2026)'),
    ]);

    await tester.tap(find.text('Ora disponibile: Dune (2021)'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/item/ee39');

    // Di nuovo nella pagina con il pannello: il contenitore è lo stesso.
    router.go('/');
    await tester.pumpAndSettle();
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    await tester.tap(find.text('Ora disponibile: Brothers (2026)'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/requests?tab=mine');
  });
}
