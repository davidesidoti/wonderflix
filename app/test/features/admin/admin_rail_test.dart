import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';
import 'package:wonderflix/features/admin/admin_rail.dart';
import 'package:wonderflix/features/admin/admin_screen.dart';
import 'package:wonderflix/features/admin/server_strip.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;

  setUp(() {
    api = FakeAdminApi()
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
  });

  const all = SocialFeatures(
      inbox: true, account: true, downloads: true, space: true);
  const wide = Size(1440, 900);
  const narrow = Size(390, 844);

  Key tabKey(AdminTab t) => ValueKey('admin-tab-${t.name}');

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = wide,
    SocialFeatures features = all,
  }) async {
    await pumpApp(
      tester,
      const Scaffold(body: AdminScreen()),
      overrides: adminTestOverrides(api, features: features),
      surfaceSize: size,
      touch: size == narrow,
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpWidgetUnderTest(
      WidgetTester tester, Widget child, {Size size = wide}) async {
    await pumpApp(
      tester,
      Scaffold(body: child),
      overrides: adminTestOverrides(api, features: all),
      surfaceSize: size,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
  }

  LampState lampOfServer(WidgetTester tester) => tester
      .widget<WfLamp>(find.descendant(
          of: find.byType(ServerStrip), matching: find.byType(WfLamp)))
      .state;

  group('largo', () {
    testWidgets('la colonna sostituisce il titolo e ha le sette voci',
        (tester) async {
      await pumpPage(tester);

      expect(find.byType(AdminRail), findsOneWidget);
      expect(find.byType(AdminTabStrip), findsNothing);
      expect(find.text('AMMINISTRAZIONE'), findsNothing);
      for (final tab in AdminTab.values) {
        expect(find.byKey(tabKey(tab)), findsOneWidget, reason: tab.name);
      }
      expect(tester.getSize(find.byType(AdminRail)).width, 208);
    });

    testWidgets('senza la funzione download manca la voce', (tester) async {
      await pumpPage(tester,
          features: const SocialFeatures(
              inbox: true, account: true, downloads: false, space: true));

      expect(find.byKey(tabKey(AdminTab.downloads)), findsNothing);
      expect(find.byKey(tabKey(AdminTab.space)), findsOneWidget);
    });

    testWidgets('le etichette della colonna hanno spazio', (tester) async {
      await pumpPage(tester);

      final label = find.descendant(
          of: find.byKey(tabKey(AdminTab.maintenance)),
          matching: find.text('Manutenzione'));
      expect(tester.getSize(label).width, greaterThanOrEqualTo(120));
    });

    testWidgets('i titoli delle schede stanno alla stessa altezza',
        (tester) async {
      final titles = {
        AdminTab.sessions: 'Sessioni',
        AdminTab.users: 'Utenti',
        AdminTab.maintenance: 'Manutenzione',
        AdminTab.wonderflix: 'WonderFlix',
      };
      final tops = <AdminTab, double>{};
      for (final MapEntry(key: tab, value: title) in titles.entries) {
        await pumpApp(
          tester,
          Scaffold(body: AdminScreen(tab: tab)),
          overrides: adminTestOverrides(api, features: all),
          surfaceSize: wide,
        );
        await tester.pumpAndSettle();
        tops[tab] = tester.getTopLeft(find.descendant(
            of: find.byType(AdminTabTitle), matching: find.text(title))).dy;
      }

      expect(tops.values.toSet().length, 1, reason: '$tops');
      expect(tops.values.first, greaterThan(0));
    });

    testWidgets('il blocco del server sta in cima alla colonna',
        (tester) async {
      await pumpPage(tester);

      final strip = tester.getRect(find.byType(ServerStrip));
      expect(strip.bottom,
          lessThanOrEqualTo(tester.getTopLeft(find.byKey(tabKey(AdminTab.sessions))).dy));
      expect(strip.left, greaterThanOrEqualTo(0));
      expect(strip.right, lessThanOrEqualTo(208));
      expect(lampOfServer(tester), LampState.ok);
    });

    testWidgets('server in errore: Riprova e Riavvia, anche con la scheda in '
        'errore', (tester) async {
      api
        ..serverInfoError = const ServerUnreachableException()
        ..sessionsError = const ServerUnreachableException();
      await pumpPage(tester);

      expect(find.text('Riprova'), findsWidgets);
      expect(find.text('Riavvia'), findsOneWidget);
      expect(lampOfServer(tester), LampState.broken);
    });
  });

  group('stretto', () {
    testWidgets('la fila al posto della colonna', (tester) async {
      await pumpPage(tester, size: narrow);

      expect(find.byType(AdminTabStrip), findsOneWidget);
      expect(find.byType(AdminRail), findsNothing);
      expect(find.text('AMMINISTRAZIONE'), findsNothing);
      expect(find.byType(ServerStrip), findsOneWidget);
    });

    testWidgets('scorrendo la scheda escono il blocco del server e la fila',
        (tester) async {
      api.sessionsValue = [
        for (var i = 0; i < 12; i++)
          testSession('s$i', 'utente$i', playing: testMovie),
      ];
      await pumpPage(tester, size: narrow);

      final list = find.byType(ListView).first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
      }

      expect(find.byType(ServerStrip), findsNothing);
      expect(find.byType(AdminTabStrip), findsNothing);
    });

    testWidgets('cambiando scheda la fila riporta in vista la voce scelta',
        (tester) async {
      final router = GoRouter(initialLocation: '/admin', routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => Scaffold(
              body: AdminScreen(
                  tab: AdminTab.parse(state.uri.queryParameters['tab']))),
        ),
      ]);
      await pumpAppRouter(tester, router,
          overrides: adminTestOverrides(api, features: all),
          surfaceSize: narrow,
          touch: true);
      await tester.pumpAndSettle();

      final last = find.byKey(tabKey(AdminTab.wonderflix));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();

      // La scheda nuova rimonta la fila da zero: la voce scelta deve vedersi.
      final rect = tester.getRect(find.byKey(tabKey(AdminTab.wonderflix)));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(390));
      expect(find.text('Annuncio'), findsOneWidget);
    });

    testWidgets('aprire una scheda lunga non fa scorrere via il blocco del '
        'server', (tester) async {
      final router = GoRouter(initialLocation: '/admin', routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => Scaffold(
              body: AdminScreen(
                  tab: AdminTab.parse(state.uri.queryParameters['tab']))),
        ),
      ]);
      await pumpAppRouter(tester, router,
          overrides: adminTestOverrides(api, features: all),
          surfaceSize: narrow,
          touch: true);
      await tester.pumpAndSettle();

      final last = find.byKey(tabKey(AdminTab.wonderflix));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();

      final vertical = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable))
          .first);
      expect(vertical.position.pixels, 0);
      expect(tester.getTopLeft(find.byType(ServerStrip)).dy, greaterThanOrEqualTo(0));
      expect(find.text('Riavvia').hitTestable(), findsOneWidget);
    });

    testWidgets('server in errore: Riprova e Riavvia, anche con la scheda in '
        'errore', (tester) async {
      api
        ..serverInfoError = const ServerUnreachableException()
        ..sessionsError = const ServerUnreachableException();
      await pumpPage(tester, size: narrow);

      expect(find.text('Riprova'), findsWidgets);
      expect(find.text('Riavvia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('blocco del server', () {
    testWidgets('riavvio necessario: testo e spia oro', (tester) async {
      api.serverInfoValue = const ServerInfo(
          name: 'WonderFlix', version: '10.11.9', hasPendingRestart: true);
      await pumpPage(tester);

      expect(find.byKey(const Key('pending-restart')), findsOneWidget);
      expect(lampOfServer(tester), LampState.attention);
    });

    testWidgets('primo caricamento: spia spenta, poi verde', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: AdminScreen()),
        overrides: adminTestOverrides(api, features: all),
      );
      expect(lampOfServer(tester), LampState.off);

      await tester.pumpAndSettle();
      expect(lampOfServer(tester), LampState.ok);
    });
  });

  group('contatori', () {
    final playing = testMovie;

    testWidgets('il numero sta dentro la voce', (tester) async {
      api.sessionsValue = [
        testSession('a', 'anna', playing: playing),
        testSession('b', 'bruno', playing: playing),
      ];
      await pumpWidgetUnderTest(
          tester,
          const AdminRail(
              tabs: [AdminTab.sessions, AdminTab.maintenance],
              current: AdminTab.maintenance));

      expect(
          find.descendant(
              of: find.byKey(tabKey(AdminTab.sessions)),
              matching: find.text('2')),
          findsOneWidget);
    });

    testWidgets('con zero niente pallino', (tester) async {
      api.sessionsValue = [testSession('a', 'anna')];
      await pumpWidgetUnderTest(
          tester,
          const AdminRail(
              tabs: [AdminTab.sessions, AdminTab.maintenance],
              current: AdminTab.maintenance));

      expect(
          find.descendant(
              of: find.byKey(tabKey(AdminTab.sessions)),
              matching: find.text('0')),
          findsNothing);
    });

    testWidgets('la fila ha gli stessi contatori', (tester) async {
      api.sessionsValue = [testSession('a', 'anna', playing: playing)];
      await pumpWidgetUnderTest(
          tester,
          const AdminTabStrip(
              tabs: [AdminTab.sessions, AdminTab.maintenance],
              current: AdminTab.maintenance),
          size: narrow);

      expect(
          find.descendant(
              of: find.byKey(tabKey(AdminTab.sessions)),
              matching: find.text('1')),
          findsOneWidget);
    });
  });

  testWidgets('la voce scelta è selezionata per l\'accessibilità',
      (tester) async {
    await pumpWidgetUnderTest(
        tester,
        const AdminRail(
            tabs: [AdminTab.sessions, AdminTab.users],
            current: AdminTab.users));

    bool selected(AdminTab t) => tester
        .widget<Semantics>(find
            .ancestor(
                of: find.byKey(tabKey(t)), matching: find.byType(Semantics))
            .first)
        .properties
        .selected!;
    expect(selected(AdminTab.users), isTrue);
    expect(selected(AdminTab.sessions), isFalse);
  });

  testWidgets('con la tastiera il focus è visibile sulla voce', (tester) async {
    await pumpWidgetUnderTest(
        tester,
        const AdminRail(
            tabs: [AdminTab.sessions, AdminTab.users],
            current: AdminTab.sessions));
    expect(find.byKey(const ValueKey('admin-tab-focus')), findsNothing);

    // Il primo Tab va a Riavvia, il secondo alla prima voce.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(
        find.descendant(
            of: find.byKey(tabKey(AdminTab.sessions)),
            matching: find.byKey(const ValueKey('admin-tab-focus'))),
        findsOneWidget);
  });
}
