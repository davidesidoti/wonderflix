import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_account_row.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  /// Apre il pannello con [entries] in un router con Impostazioni.
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
        GoRoute(
            path: '/settings',
            builder: (context, state) => const Text('impostazioni')),
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
    return (router, container);
  }

  testWidgets('il clic apre Impostazioni e chiude il pannello',
      (tester) async {
    final (router, container) = await pumpPanel(
        tester, [testContactReminder(channels: const [AccountChannel.email])]);

    expect(find.text('Proteggi il tuo account'), findsOneWidget);
    expect(
        find.text('Collega la tua email per recuperare la password se la '
            'dimentichi.'),
        findsOneWidget);

    await tester.tap(find.text('Proteggi il tuo account'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/settings');
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  test('i testi per i canali del server', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(inboxContactReminderText(l, const [AccountChannel.discord]),
        'Collega Discord per recuperare la password se la dimentichi.');
    expect(inboxContactReminderText(l, const [AccountChannel.email]),
        'Collega la tua email per recuperare la password se la dimentichi.');
    const both = 'Collega Discord o la tua email per recuperare la password '
        'se la dimentichi.';
    expect(
        inboxContactReminderText(
            l, const [AccountChannel.discord, AccountChannel.email]),
        both);
    expect(inboxContactReminderText(l, const []), both);
  });
}
