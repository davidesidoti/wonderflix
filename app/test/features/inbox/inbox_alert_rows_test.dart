import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/inbox/notification_text.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/form_factor.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

final _at = DateTime.utc(2026, 10, 31, 10);

void main() {
  /// Il pannello in un router con le rotte di destinazione; [width] 360 è il
  /// layout stretto.
  Future<(GoRouter, ProviderContainer)> pumpPanel(
      WidgetTester tester, List<InboxEntry> entries,
      {double width = 1440}) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: entries, unread: entries.length);
    await tester.binding.setSurfaceSize(Size(width, 2400));
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
        GoRoute(path: '/requests', builder: (_, _) => const Text('richieste')),
        GoRoute(path: '/admin', builder: (_, _) => const Text('admin')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const SizedBox.shrink()),
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

  final alerts = <InboxEntry>[
    RequestApprovedEntry(
        id: 'a1', seq: 10, createdAt: _at, read: false, title: 'Dune (2021)'),
    RequestDeclinedEntry(
        id: 'a2', seq: 9, createdAt: _at, read: false, title: 'Brothers'),
    DownloadNeedsYouEntry(
        id: 'a3',
        seq: 8,
        createdAt: _at,
        read: false,
        title: 'Severance S02',
        reason: 'GrabRefused'),
    DownloadStalledEntry(
        id: 'a4', seq: 7, createdAt: _at, read: false, title: 'Dark'),
    LightenBlockedEntry(
        id: 'a5', seq: 6, createdAt: _at, read: false, title: 'Heat'),
    SpaceOperationFailedEntry(id: 'a6', seq: 5, createdAt: _at, read: false),
    DiskAlmostFullEntry(
        id: 'a7', seq: 4, createdAt: _at, read: false, percent: 93),
    RecoveryStartedEntry(
        id: 'a8', seq: 3, createdAt: _at, read: false, userName: 'Garg'),
    RecoveryBlockedEntry(
        id: 'a9', seq: 2, createdAt: _at, read: false, everyone: true),
    RestartPendingEntry(id: 'a10', seq: 1, createdAt: _at, read: false),
  ];

  testWidgets('ogni voce nuova mostra titolo e testo del catalogo',
      (tester) async {
    await pumpPanel(tester, alerts);
    final l = AppLocalizations.of(tester.element(find.byType(InboxPanel)));
    for (final entry in alerts) {
      final tile = find.byKey(Key('inbox-alert-${entry.id}'));
      await tester.ensureVisible(tile);
      final text = notificationTextOf(entry, l);
      expect(tile, findsOneWidget, reason: entry.id);
      expect(find.descendant(of: tile, matching: find.text(text.title)),
          findsOneWidget,
          reason: entry.id);
      if (text.body.isNotEmpty) {
        expect(find.descendant(of: tile, matching: find.text(text.body)),
            findsOneWidget,
            reason: entry.id);
      }
    }
  });

  testWidgets('un tocco chiude il pannello e va alla rotta con context.go',
      (tester) async {
    final (router, container) = await pumpPanel(tester, alerts);
    final l = AppLocalizations.of(tester.element(find.byType(InboxPanel)));
    for (final entry in alerts) {
      router.go('/');
      await tester.pumpAndSettle();
      container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
      await tester.pump();
      final tile = find.byKey(Key('inbox-alert-${entry.id}'));
      await tester.ensureVisible(tile);
      await tester.tap(find.descendant(
          of: tile, matching: find.text(notificationTextOf(entry, l).title)));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), notificationTextOf(entry, l).route,
          reason: entry.id);
      expect(container.read(shellPanelProvider), ShellPanel.none,
          reason: entry.id);
    }
  });

  testWidgets('RequestApproved ha la stessa icona tonda di RequestAvailable',
      (tester) async {
    await pumpPanel(tester, [
      testRequestAvailable(id: 'r1', seq: 2),
      RequestApprovedEntry(
          id: 'a1', seq: 1, createdAt: _at, read: false, title: 'Dune (2021)'),
    ]);
    expect(find.byIcon(LucideIcons.clapperboard), findsNWidgets(2));
  });

  testWidgets('nel layout stretto (360) il testo va a capo senza overflow',
      (tester) async {
    final long = 'x' * 60;
    await pumpPanel(
        tester,
        [
          DownloadNeedsYouEntry(
              id: 'a3',
              seq: 8,
              createdAt: _at,
              read: false,
              title: 'Un titolo molto lungo con parole $long',
              reason: 'GrabRefused'),
        ],
        width: 360);
    expect(FormFactor.of(tester.element(find.byType(InboxPanel))).compact,
        isTrue);
    expect(tester.takeException(), isNull);
    final tile = find.byKey(const Key('inbox-alert-a3'));
    expect(tester.getSize(tile).width, lessThanOrEqualTo(360));
    expect(tester.getSize(tile).height, greaterThan(44));
  });
}
